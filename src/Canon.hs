module Canon
  ( runCanon
  , dispatch
  , usage
  ) where

import System.Environment (getArgs)

runCanon :: IO ()
runCanon = getArgs >>= putStrLn . dispatch

dispatch :: [String] -> String
dispatch ["version"] = "canon 0.1.0.0"
dispatch _ = usage

usage :: String
usage =
  unlines
    [ "canon - canonical project documentation"
    , ""
    , "Usage:"
    , "  canon version"
    ]
