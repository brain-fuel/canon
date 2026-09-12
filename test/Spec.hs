module Main (main) where

import Canon (dispatch, usage)
import System.Exit (exitFailure)

main :: IO ()
main =
  if dispatch ["version"] == "canon 0.1.0.0" && dispatch [] == usage
    then putStrLn "canon-test: all checks passed"
    else exitFailure
