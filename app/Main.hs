-- | The executable is a one-line shim so that everything testable lives in the library.
module Main (main) where

import Canon (runCanon)

-- | Delegates to the library entry point so the executable carries no logic of its own.
main :: IO ()
main = runCanon
