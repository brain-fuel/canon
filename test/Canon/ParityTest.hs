-- | canon reads every language LawSpec targets, now or by plan, so the root canon.yaml pins that
-- list and these properties hold the repository to it: each listed language has a grammar, a
-- profile, a canonically commented dialect, and a sample, and no grammar is outside the list.
-- ref:DEC-lawspec-parity ref:REQ-lawspec-parity
module Canon.ParityTest (tests) where

import Canon.Config (Config (..), readConfigFile, renderConfigError)
import Canon.Profile (GrammarSource (..), Profile (..))
import Control.Monad (filterM, forM)
import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Yaml as Yaml
import Hedgehog (Property, PropertyT, annotate, evalIO, failure, property, withTests, (===))
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (normalise, splitDirectories, takeExtension, (</>))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

-- | The test group this module contributes to the suite.
tests :: TestTree
tests =
  testGroup
    "parity"
    [ testProperty "every LawSpec target has a grammar, a profile, a dialect, and a sample" prop_everyLawSpecTargetHasAGrammarAProfileADialectAndASample
    , testProperty "every grammar directory belongs to a LawSpec target" prop_everyGrammarDirectoryBelongsToALawSpecTarget
    ]

-- | The parity section of the root canon.yaml: the languages LawSpec targets now and by plan, and
-- for a language whose pieces another branch delivers, which pieces are still to come.
data Parity = Parity
  { parityCurrent :: [Text]
  , parityPlanned :: [Text]
  , parityPending :: Map Text [Text]
  }

instance FromJSON Parity where
  parseJSON = withObject "Parity" $ \o -> Parity <$> o .: "current" <*> o .: "planned" <*> (fromMaybe Map.empty <$> o .:? "pending")

-- | The root configuration's parity section, which canon itself does not read.
newtype Root = Root Parity

instance FromJSON Root where
  parseJSON = withObject "Root" $ \o -> Root <$> o .: "parity"

-- | The four pieces a language must have, by the names the pending map uses.
pieces :: [Text]
pieces = ["grammar", "profile", "dialect", "sample"]

-- | Reads the parity section.
readParity :: PropertyT IO Parity
readParity = do
  decoded <- evalIO (Yaml.decodeFileEither "canon.yaml")
  case decoded of
    Right (Root parity) -> pure parity
    Left e -> annotate (Yaml.prettyPrintParseException e) >> failure

-- | Every project of the repository, the root and each sample, with the languages its canon.yaml
-- declares and the grammar directory each profile names, relative to the repository root.
projects :: PropertyT IO [(FilePath, Map Text FilePath)]
projects = do
  samples <- evalIO (sort <$> listDirectory "lang_samples")
  sampleDirs <- evalIO (filterM (\d -> doesFileExist (d </> "canon.yaml")) ["lang_samples" </> s | s <- samples])
  forM ("." : sampleDirs) $ \dir -> do
    loaded <- evalIO (readConfigFile (dir </> "canon.yaml"))
    config <- either (\e -> annotate (T.unpack (renderConfigError e)) >> failure) pure loaded
    pure (dir, Map.mapMaybe (grammarDirectory dir . profileGrammar) (configLanguages config))

-- | The directory under grammars/ that holds a profile's grammar, whether the profile names the
-- plain grammar or its canonically commented dialect.
grammarDirectory :: FilePath -> GrammarSource -> Maybe FilePath
grammarDirectory dir source = case dropWhile (/= "grammars") (splitDirectories (normalise (dir </> path))) of
  ("grammars" : name : _) -> Just ("grammars" </> name)
  _ -> Nothing
  where
    path = case source of
      CombinedGrammarFile p -> p
      SplitGrammarFiles lexer _ -> lexer

-- | Whether a directory holds a grammar file.
holdsGrammar :: FilePath -> IO Bool
holdsGrammar dir = do
  present <- doesDirectoryExist dir
  if present then any ((== ".g4") . takeExtension) <$> listDirectory dir else pure False

-- | The parity list is LawSpec's set of target languages, each named by its profile's key or its
-- grammar's directory, so a target canon cannot read, document
-- by its own conventions, or show on real code is a gap in what LawSpec can rely on. A language a
-- branch still to be merged completes names the pieces it still lacks under pending, and a pending
-- piece that exists is reported too, so the list never claims less than the repository holds.
-- ref:REQ-lawspec-parity ref:DEC-lawspec-parity
prop_everyLawSpecTargetHasAGrammarAProfileADialectAndASample :: Property
prop_everyLawSpecTargetHasAGrammarAProfileADialectAndASample = withTests 1 $ property $ do
  parity <- readParity
  found <- projects
  let listed = parityCurrent parity ++ parityPlanned parity
      grammarsOf lang = [g | (_, langs) <- found, (l, g) <- Map.toList langs, names lang l g]
      samplesOf lang = [d | (d, langs) <- found, any (uncurry (names lang)) (Map.toList langs)]
  present <- forM listed $ \lang -> do
    let dirs = grammarsOf lang
    grammar <- evalIO (or <$> mapM holdsGrammarOrDialect dirs)
    dialect <- evalIO (or <$> mapM (\d -> holdsGrammar (d </> "canonically_commented")) dirs)
    pure (lang, [p | (p, True) <- zip pieces [grammar, not (null dirs), dialect, not (null (samplesOf lang))]])
  let missing = [(lang, [p | p <- pieces, p `notElem` have]) | (lang, have) <- present]
  Map.fromList [m | m@(_, _ : _) <- missing] === Map.filter (not . null) (parityPending parity)
  Set.toList (Set.fromList listed) === sort listed
  where
    -- A listed name names a profile by its key, or by its grammar's directory, as yaml names the
    -- grammar the pulumi profile reads.
    names lang l g = l == lang || g == "grammars" </> T.unpack lang
    holdsGrammarOrDialect d = (||) <$> holdsGrammar d <*> holdsGrammar (d </> "canonically_commented")

-- | A grammar no listed language uses is a language canon reads that LawSpec does not target, or a
-- target missing from the list; either way the list and the repository have drifted.
-- ref:REQ-lawspec-parity ref:DEC-lawspec-parity
prop_everyGrammarDirectoryBelongsToALawSpecTarget :: Property
prop_everyGrammarDirectoryBelongsToALawSpecTarget = withTests 1 $ property $ do
  parity <- readParity
  found <- projects
  directories <- evalIO (sort <$> listDirectory "grammars")
  let listed = Set.fromList (parityCurrent parity ++ parityPlanned parity)
      used = Set.fromList ([g | (_, langs) <- found, (lang, g) <- Map.toList langs, Set.member lang listed] ++ ["grammars" </> T.unpack l | l <- Set.toList listed])
  [d | d <- directories, not (Set.member ("grammars" </> d) used)] === []
