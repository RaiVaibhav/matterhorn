module Scripts
  ( findAndRunScript
  , listScripts
  )
where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Text as T
import Data.Monoid ((<>))
import qualified Control.Concurrent.STM as STM
import System.Exit (ExitCode(..))
import Lens.Micro.Platform (use)

import Types
import State (sendMessage, runLoggedCommand)
import State.Common
import FilePaths (Script(..), getAllScripts, locateScriptPath)

findAndRunScript :: T.Text -> T.Text -> MH ()
findAndRunScript scriptName input = do
    fpMb <- liftIO $ locateScriptPath (T.unpack scriptName)
    outputChan <- use (csResources.crSubprocessLog)
    case fpMb of
      ScriptPath scriptPath -> do
        doAsyncWith Preempt $ runScript outputChan scriptPath input
      NonexecScriptPath scriptPath -> do
        let msg = ("The script `" <> T.pack scriptPath <> "` cannot be " <>
             "executed. Try running\n" <>
             "```\n" <>
             "$ chmod u+x " <> T.pack scriptPath <> "\n" <>
             "```\n" <>
             "to correct this error. " <> scriptHelpAddendum)
        postErrorMessage msg
      ScriptNotFound -> do
        let msg = ("No script named " <> scriptName <> " was found")
        postErrorMessage msg

runScript :: STM.TChan ProgramOutput -> FilePath -> T.Text -> IO (MH ())
runScript outputChan fp text = do
  po <- runLoggedCommand True outputChan fp [] (Just $ T.unpack text)
  return $ case programExitCode po of
    ExitSuccess -> do
        when (null $ programStderr po) $ do
            mode <- use (csEditState.cedEditMode)
            sendMessage mode (T.pack $ programStdout po)
    ExitFailure _ -> return ()

listScripts :: MH ()
listScripts = do
  (execs, nonexecs) <- liftIO getAllScripts
  let scripts = ("Available scripts are:\n" <>
                 mconcat [ "  - " <> T.pack cmd <> "\n"
                         | cmd <- execs
                         ])
  postInfoMessage scripts
  case nonexecs of
    [] -> return ()
    _  -> do
      let errMsg = ("Some non-executable script files are also " <>
                    "present. If you want to run these as scripts " <>
                    "in Matterhorn, mark them executable with \n" <>
                    "```\n" <>
                    "$ chmod u+x [script path]\n" <>
                    "```\n" <>
                    "\n" <>
                    mconcat [ "  - " <> T.pack cmd <> "\n"
                            | cmd <- nonexecs
                            ] <> "\n" <> scriptHelpAddendum)
      postErrorMessage errMsg

scriptHelpAddendum :: T.Text
scriptHelpAddendum =
  "For more help with scripts, run the command\n" <>
  "```\n/help scripts\n```\n"
