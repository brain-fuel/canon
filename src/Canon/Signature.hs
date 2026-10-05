-- | A signature file declares what its implementation exports, as F#'s .fsi does its .fs: the
-- compiler takes the documentation of what both declare from the signature, and what the signature
-- leaves out is private to the implementation. So where both files of a name are checked, a unit of
-- the implementation needs no comment, and a unit of the signature needs one when the unit it
-- declares would. Units are matched by the names of the units that enclose them, whatever their
-- kinds, since a val in a signature declares a let in its implementation. ref:DEC-fsharp-signatures
module Canon.Signature
  ( linkSignatures
  ) where

import Canon.Extract.Grammar (Extraction (..))
import Canon.Model
import Canon.Profile (Profile (..), profileForPath)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (replaceExtension, takeExtension)

-- | Moves the comment requirement of every unit an implementation shares with its signature onto
-- the signature, and lifts it from what the implementation keeps to itself; a test keeps its own.
linkSignatures :: Map Text Profile -> [(FilePath, Either e Extraction)] -> [(FilePath, Either e Extraction)]
linkSignatures profiles extracted = map link extracted
  where
    byPath = Map.fromList [(p, e) | (p, Right e) <- extracted]
    pairs path = case profileForPath profiles path of
      Just (_, profile) -> Map.toList (profileSignatures profile)
      Nothing -> []
    counterpart path =
      case [(False, replaceExtension path (T.unpack sig)) | (sig, impl) <- pairs path, T.pack (takeExtension path) == impl]
        ++ [(True, replaceExtension path (T.unpack impl)) | (sig, impl) <- pairs path, T.pack (takeExtension path) == sig] of
        ((isSignature, other) : _) -> (,) isSignature <$> Map.lookup other byPath
        [] -> Nothing
    link entry = case entry of
      (path, Right e) | Just (isSignature, other) <- counterpart path ->
        (path, Right (if isSignature then asSignature other e else asImplementation e))
      _ -> entry
    asImplementation e = e {extractionModel = mapUnits (\_ u -> if unitTest u then u else u {unitRequirement = Optional}) (extractionModel e)}
    asSignature impl e =
      let needed = Map.fromList [(k, unitRequirement u) | (k, u) <- keyed (extractionModel impl)]
          lift k u = if Map.lookup k needed == Just Required then u {unitRequirement = Required} else u
       in e {extractionModel = mapUnits lift (extractionModel e)}

-- | Every unit below the files of a model with the names of the units from the file down to it.
keyed :: Model ev -> [([Text], CodeUnit ev)]
keyed model = concatMap (\root -> concatMap (go []) (unitChildren root)) (modelUnits model)
  where
    go names u = let k = names ++ [whatName (answerValue (unitWhat u))] in (k, u) : concatMap (go k) (unitChildren u)

-- | Rewrites every unit below the files of a model, given the names that lead to it.
mapUnits :: ([Text] -> CodeUnit ev -> CodeUnit ev) -> Model ev -> Model ev
mapUnits f model = model {modelUnits = map (\root -> root {unitChildren = map (go []) (unitChildren root)}) (modelUnits model)}
  where
    go names u =
      let k = names ++ [whatName (answerValue (unitWhat u))]
          u' = f k u
       in u' {unitChildren = map (go k) (unitChildren u)}
