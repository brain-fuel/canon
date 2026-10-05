-- | Test suites of several checkouts run at once on one machine, so a test's scratch directory must
-- be its own: a fixed name let one run delete or overwrite another's files mid-test, which showed
-- as tests failing, or never finishing, only when several suites ran together.
module Canon.Scratch (withScratch) where

import Control.Exception (bracket, throwIO)
import System.Directory (createDirectory, getTemporaryDirectory, removeDirectoryRecursive)
import System.FilePath ((</>))
import System.IO.Error (isAlreadyExistsError, tryIOError)

-- | Runs an action in a directory no other run holds, made by creating it atomically under a name
-- not yet taken, and removes it afterwards.
withScratch :: String -> (FilePath -> IO a) -> IO a
withScratch name = bracket make removeDirectoryRecursive
  where
    make = do
      base <- getTemporaryDirectory
      let attempt n = do
            let dir = base </> ("canon-test-" ++ name ++ "-" ++ show (n :: Int))
            made <- tryIOError (createDirectory dir)
            case made of
              Right () -> pure dir
              Left e | isAlreadyExistsError e -> attempt (n + 1)
              Left e -> throwIO e
      attempt 0
