-- | Extraction through Folio pages: the units of a tangled file are found by parsing what the
-- pages tangle to, with the embedded language's own grammar, and then relocated into the pages,
-- so every rule of the language applies unchanged and every finding points at a page. A page is
-- a unit of its own, kind doc, whose Why is all its prose. ref:DEC-units-by-tangled-path
-- ref:DEC-section-prose-is-why ref:DEC-doc-kind
module Canon.Extract.Folio
  ( relocate
  , pageExtraction
  , pageUnitId
  , isDocUnitId
  , blockDefinitionFindings
  , frontMatterFindings
  , duplicateIdFindings
  , proseText
  ) where

import Canon.CanonicalComment (parseCanonicalComment, toWhy)
import Canon.Config (Config (..))
import Canon.Extract.Grammar (Extraction (..))
import Canon.Folio (Block (..), Document (..), quadrants)
import Canon.Model
import Canon.Model.Finding (Finding (..))
import Canon.Span (Position (..), Span (..))
import Canon.Tangle (Origin (..), Tangled (..))
import Data.Char (isAsciiLower, isDigit)
import Data.List (dropWhileEnd)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (splitDirectories, takeDirectory)

-- | The prose of a block or a page as one text, trailing blank lines dropped.
proseText :: [(Int, Text)] -> Text
proseText = T.intercalate "\n" . dropWhileEnd T.null . map snd

-- | Moves every span of an extraction from the tangled file into the pages that produced it: a
-- body line to its line in its page, a generated comment to the prose that generated it, and a
-- decision's Why to that prose as authored, so its digest is of the page.
relocate :: Tangled -> Extraction -> Extraction
relocate t (Extraction model findings) = Extraction model {modelUnits = relocatedUnits, modelDecisions = map decision (modelDecisions model)} (map finding findings)
  where
    relocatedUnits = map unit (modelUnits model)
    everyUnit = concatMap allUnits relocatedUnits
    -- The prose of a section documents every definition in its block, so the decision covers
    -- each unit the block holds, not only the first the generated comment sat above.
    coveredBy doc b =
      [ unitId u
      | u <- everyUnit
      , let w = answerValue (unitWhere u)
      , wherePath w == doc
      , let from = positionLine (spanStart (whereSpan w))
      , let to = positionLine (spanEnd (whereSpan w))
      , to >= blockLine b
      , from <= blockLine b + length (blockBody b) + 1
      ]
    origins = Map.fromList (zip [1 ..] (tangledOrigins t))
    blocks = Map.fromList [((blockSource b, blockLine b), b) | b <- tangledBlocks t]
    -- The page and line a tangled line comes from; a generated comment line points at its prose.
    located n = case Map.lookup n origins of
      Just (OriginBody doc line) -> Just (doc, line)
      Just (OriginDoc doc line) -> Just (doc, maybe line (fst . proseSpan) (Map.lookup (doc, line) blocks))
      _ -> Nothing
    proseSpan b = case blockProse b of
      [] -> (blockLine b, blockLine b)
      ps -> (fst (head' ps), fst (last ps))
    head' (x : _) = x
    head' [] = (0, "")
    docLast doc = maximum (1 : [line | OriginBody d line <- tangledOrigins t, d == doc])
    -- A span starts where its first line went; it ends at its last line if that is in the same
    -- page, else at the last line the page contributes.
    relocateSpan (Span (Position l1 c1) (Position l2 c2)) = case located l1 of
      Just (doc, from) ->
        let to = case located l2 of
              Just (doc', line) | doc' == doc -> Just (line, c2)
              _ -> Nothing
         in Just (doc, Span (Position from c1) (maybe (Position (docLast doc) 1) (uncurry Position) to))
      Nothing -> Nothing
    whereOf w = case relocateSpan (whereSpan w) of
      Just (doc, sp) -> w {wherePath = doc, whereSpan = sp}
      Nothing -> w
    evidence path e = case e of
      Asserted (Assertion _ sp) -> case relocateSpan sp of
        Just (doc, sp') -> Asserted (Assertion doc sp')
        Nothing -> e
      DerivedFromParse _ -> DerivedFromParse path
      _ -> e
    unit u =
      let w = whereOf (answerValue (unitWhere u))
          path = wherePath w
          how = case answerValue (unitHow u) of
            HowAt sp -> HowAt (maybe sp snd (relocateSpan sp))
            other -> other
       in u
            { unitWhere = Answer w (evidence path (answerEvidence (unitWhere u)))
            , unitHow = Answer how (evidence path (answerEvidence (unitHow u)))
            , unitWhat = Answer (answerValue (unitWhat u)) (evidence path (answerEvidence (unitWhat u)))
            , unitChildren = map unit (unitChildren u)
            }
    -- A decision's comment was generated from a block's prose; the decision becomes that prose.
    decision d =
      let w = decisionWhere d
          start = positionLine (spanStart (whereSpan w))
       in case Map.lookup start origins of
            Just (OriginDoc doc line) | Just b <- Map.lookup (doc, line) blocks ->
              let (from, to) = proseSpan b
                  sp = Span (Position from 1) (Position to (1 + T.length (fromMaybe "" (lookup to (blockProse b)))))
                  covered = NonEmpty.head (decisionUnits d) :| [u | u <- coveredBy doc b, u /= NonEmpty.head (decisionUnits d)]
               in d
                    { decisionUnits = covered
                    , decisionWhy = Answer (toWhy (parseCanonicalComment (proseText (blockProse b)))) (Asserted (Assertion doc sp))
                    , decisionWhere = w {wherePath = doc, whereSpan = sp}
                    }
            _ -> d {decisionWhere = whereOf w, decisionWhy = Answer (answerValue (decisionWhy d)) (evidence (wherePath (whereOf w)) (answerEvidence (decisionWhy d)))}
    finding f = case f of
      OrphanDocComment _ sp -> case relocateSpan sp of
        Just (doc, sp') -> OrphanDocComment doc sp'
        Nothing -> f
      _ -> f

-- | The id of a page's own unit: the language, the page's path, and the kind doc with the page's
-- id.
pageUnitId :: FilePath -> Text -> UnitId
pageUnitId path pageId = UnitId ("folio" :| [T.pack d | d <- splitDirectories path, d /= "."] ++ ["doc", pageId])

-- | Whether a unit id is a page's.
isDocUnitId :: UnitId -> Bool
isDocUnitId (UnitId segments) = NonEmpty.head segments == "folio" && case reverse (NonEmpty.toList segments) of
  (_ : "doc" : _) -> True
  _ -> False

-- | A page as an extraction: one unit of kind doc, named by its id, with one decision whose Why
-- is all the page's prose with its citations, plus the video it names, so the existing checks
-- resolve and count them.
pageExtraction :: Config -> Document -> Extraction
pageExtraction config doc = Extraction (Model "folio" (configVersion config) Nothing [root] [decision]) []
  where
    path = docPath doc
    pageId = fromMaybe (T.pack path) (Map.lookup "id" (docFront doc))
    uid = pageUnitId path pageId
    lastLine = maximum (1 : map fst (docProse doc) ++ map (\b -> blockLine b + length (blockBody b) + 1) (docBlocks doc))
    whole = Span (Position 1 1) (Position lastLine 1)
    evidence = DerivedFromParse path
    why = (toWy (proseText (docProse doc))) {whyReferences = whyReferences (toWy (proseText (docProse doc))) ++ mapMaybe videoKey [Map.lookup "video" (docFront doc)]}
    toWy = toWhy . parseCanonicalComment
    videoKey v = case v of
      Just k | isReferenceKey k -> Just (ReferenceKey k)
      _ -> Nothing
    root =
      CodeUnit
        { unitId = uid
        , unitWhat = Answer (What pageId (UnitKind "doc") (Map.lookup "title" (docFront doc))) evidence
        , unitHow = Answer (HowAt whole) evidence
        , unitWhere = Answer (Where path whole [] Nothing) evidence
        , unitWho = Nothing
        , unitWhen = Nothing
        , unitRequirement = Required
        , unitTest = False
        , unitChildren = []
        }
    decision =
      Decision
        { decisionId = decisionIdFor uid
        , decisionUnits = uid :| []
        , decisionWhy = Answer why (Asserted (Assertion path whole))
        , decisionWhere = Where path whole [] Nothing
        , decisionVetting = Nothing
        }

-- | A block that declares def= must have a unit of that name inside it once units are known.
blockDefinitionFindings :: [Block] -> [CodeUnit ev] -> [Finding]
blockDefinitionFindings blocks units =
  [ BlockDoesNotDefine (blockSource b) (blockLine b) (blockName b)
  | b <- blocks
  , blockDeclared b
  , not (blockIsPart b)
  , not (any (defines b) units)
  ]
  where
    -- A unit's span may start at the prose that documents it, so the unit and the block overlap.
    defines b u =
      let w = answerValue (unitWhere u)
          from = positionLine (spanStart (whereSpan w))
          to = positionLine (spanEnd (whereSpan w))
       in wherePath w == blockSource b && to >= blockLine b && from <= blockLine b + length (blockBody b) + 1 && whatName (answerValue (unitWhat u)) == blockName b

-- | The front matter a page must carry: an id of lowercase words joined by dots, and a kind that
-- names a Diátaxis quadrant and matches the directory the page lives in.
frontMatterFindings :: Document -> [Finding]
frontMatterFindings doc = case docFrontSpan doc of
  Nothing -> [FrontMatterMissing path]
  Just _ ->
    [DocIdInvalid path i | Just i <- [Map.lookup "id" front], not (validId i)]
      ++ [DocIdInvalid path "" | Nothing <- [Map.lookup "id" front]]
      ++ case Map.lookup "kind" front of
        Nothing -> [DocKindInvalid path ""]
        Just k -> case lookup k quadrants of
          Nothing -> [DocKindInvalid path k]
          Just dir -> [DocQuadrantMismatch path k | dir `notElem` splitDirectories (takeDirectory path)]
  where
    path = docPath doc
    front = docFront doc
    validId i = not (T.null i) && all word (T.splitOn "." i)
    word w = not (T.null w) && T.all (\c -> isAsciiLower c || isDigit c || c == '-') w

-- | Two pages with one id.
duplicateIdFindings :: [Document] -> [Finding]
duplicateIdFindings docs =
  [ DocIdDuplicate i a b
  | (i, paths) <- Map.toList (Map.fromListWith (++) [(i, [docPath d]) | d <- docs, Just i <- [Map.lookup "id" (docFront d)]])
  , (a : b : _) <- [reverse paths]
  ]
