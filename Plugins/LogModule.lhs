--
-- Copyright (c) 2005 Simon Winwood
-- Copyright (c) 2005 Don Stewart - http://www.cse.unsw.edu.au/~dons
-- Copyright (c) 2004 Thomas Jaeger
-- GPL version 2 or later (see http://www.gnu.org/copyleft/gpl.html)
--
-- | Logging an IRC channel..
--

> module Plugins.Log (theModule) where

> import Lambdabot
> import LBState
> import qualified IRC

> import Util ((</>))

> import Serial  ({-instances-})
> import Config

> import qualified Map as M

> import System.IO 
> import System.Time  
> import System.Directory (createDirectoryIfMissing) 

> import Control.Monad       (join)
> import Control.Monad.Trans (liftIO, MonadIO, lift)
> import Control.Monad.State (StateT, runStateT, gets, modify)

> import Maybe (fromJust, fromMaybe)

import ErrorUtils          (tryError)

------------------------------------------------------------------------

> type Channel = String

> newtype LogModule = LogModule ()

> theModule :: MODULE
> theModule = MODULE $ LogModule ()

> data Event = 
>     Said String ClockTime String
>     | Joined String ClockTime
>     | Parted String ClockTime -- covers quitting as well
>     | Renick String ClockTime String

> filterNick :: String -> [Event] -> [Event]
> filterNick who = filter filterOneNick 
>     where
>     filterOneNick (Said who' _ _) = who == who'
>     filterOneNick (Joined who' _) = who == who'
>     filterOneNick (Parted who' _)   = who == who'
>     filterOneNick (Renick old _ new) = who == old || who == new

> instance Show Event where
>     show (Said nick ct what) = timeStamp ct ++ " <" ++ nick ++ "> " ++ what
>     show (Joined nick ct)    = timeStamp ct ++ " " ++ nick ++ " joined."
>     show (Parted nick ct)    = timeStamp ct ++ " " ++ nick ++ " left."
>     show (Renick nick ct new) = timeStamp ct ++ " " ++ nick ++ " is now " ++ new ++ "."

> type DateStamp = (Int, Month, Int)
> type History   = [Event]
> type LogState = M.Map String (Handle, DateStamp, History)
 
> type Log = StateT LogState LB

------------------------------------------------------------------------

------------------------------------------------------------------------

> defaultNLines :: Int
> defaultNLines = 10

> commands :: [(String,String)]
> commands = [("last", "@last [<user>] [<count>] The last <count> (default 10) posts"),
>       ("log-email", "@log-email <email> [<start-date>] Email the log to the given address (default to todays)")]


> instance Module LogModule LogState where
>    moduleHelp _ s      = fromJust $ lookup s commands
>    moduleCmds _        = map fst commands
>    moduleDefState _    = return M.empty

>    moduleExit          = cleanLogState

Over all channels?  Maybe we want to intersect this with channels we are interested in.

>    moduleInit _        = mapM_ (\(t, f) -> ircSignalConnect t $ liftC f) 
>                            [("PRIVMSG", msgCB), ("JOIN", joinCB), ("PART", quitCB), ("QUIT", quitCB), ("NICK", nickCB)]
>              where 
>              liftC f = withLogMS $ \msg ct -> withValidLogW (f msg ct) ct (head $ IRC.channels msg)
    
>    process _ msg target "last" rest = showHistory msg target rest

FIXME --- we only do this for one channel.  Maybe allow an extra argument?

> showHistory :: IRC.Message -> String -> String -> ModuleLB LogState
> showHistory msg _ args = do
>                       fm <- readMS
>                       return [unlines . reverse $ map show $ take nLines (lines' fm)]
>     where
>     nLines = case argsS of { _:y:_ -> read y; _ -> defaultNLines }
>     lines' fm = case argsS of 
>                   x:_ -> filterNick x $ history fm
>                   _   -> history fm
>     history fm = fromMaybe [] $ M.lookup chan fm >>= \(_, _, his) -> return his
>     argsS = words args
>     chan = head $ IRC.channels msg
 
| State manipulation functions

| Cleans up after the module (closes files)

> cleanLogState :: LogModule -> ModuleT LogState LB ()
> cleanLogState  _ = 
>     withMS $ \state writer -> do
>                       liftIO $ M.fold (\(hdl, _, _) iom -> iom >> hClose hdl) (return ()) state
>                       writer M.empty

| Takes a state manipulation monad and executes it on the current
  state (and then updates it)

> withLogMS :: (IRC.Message -> ClockTime -> Log a) -> IRC.Message -> ModuleT LogState LB a
> withLogMS f msg = 
>     withMS $ \state writer -> do
>                       ct <- liftIO getClockTime
>                       (r, ls) <- runStateT (f msg ct) state
>                       writer ls
>                       return r

> openChannelFile :: Channel -> ClockTime -> Log Handle
> openChannelFile chan ct = 
>     liftIO $ createDirectoryIfMissing True dir >> openFile file AppendMode
>     where
>     file = dir ++ (dateToString date)
>     dir = outputDir config </> "/Log/" ++ host config ++ "/" ++ chan ++ "/"
>     date = dateStamp ct

> ifChannel :: Channel -> Log a -> Log a -> Log a
> ifChannel chan opT opF = do 
>                  b <- gets (M.member chan :: LogState -> Bool) 
>                  if b then opT else opF

> whenChannel :: Channel -> (Handle -> DateStamp -> History -> Bool) -> Log a -> Log a -> Log a
> whenChannel chan f opT opF = do
>                      (h, d, his) <- join $ gets (M.lookup chan)                                   
>                      if (f h d his) then opT else opF

| This function initialises the channel state (if it not already inited)

> initChannelMaybe :: String -> ClockTime -> Log ()
> initChannelMaybe chan ct = ifChannel chan (return ()) $ do         
>               hdl <- openChannelFile chan ct
>               modify (M.insert chan (hdl, date, []))
>      where
>      date = dateStamp ct

> {-
> closeChannel :: Channel -> Log ()
> closeChannel chan = do 
>             (hdl, _, _) <- join $ gets (M.lookup chan)
>             liftIO $ hClose hdl
>             modify (M.delete chan)
> -}

> reopenChannelMaybe :: Channel -> ClockTime -> Log ()
> reopenChannelMaybe chan ct = whenChannel chan (\_ d _ -> d == date) (return ()) $ do 
>             (hdl, _, _) <- join $ gets (M.lookup chan)
>             liftIO $ hClose hdl
>             hdl' <- openChannelFile chan ct
>             modify (M.adjust (\ (_, _, his) -> (hdl', date, his)) chan)
>      where
>      date = dateStamp ct

| This function ensures that the log is correctly initialised etc.

> withValidLog :: (Handle -> History -> LB (History, a)) -> ClockTime -> Channel -> Log a
> withValidLog f ct chan = do 
>                  initChannelMaybe chan ct
>                  reopenChannelMaybe chan ct
>                  (hdl, date, history) <- join $ gets (M.lookup chan)
>                  (history', rv) <- lift $ f hdl history
>                  modify (M.insert chan (hdl, date, history'))
>                  return rv

> {-
> withValidLogR :: (Handle -> History -> LB a) ->  ClockTime -> Channel -> Log a
> withValidLogR f = withValidLog (\hdl his -> f hdl his >>= \x -> return (his, x))
> -}

> withValidLogW :: (Handle -> History -> LB History) ->  ClockTime -> Channel -> Log ()
> withValidLogW f = withValidLog (\hdl his -> f hdl his >>= \x -> return (x, ()))

------------------------------------------------------------------------
-- | The bot's name, lowercase

> {-
> myname :: String
> myname = lowerCaseString (name config)
> -}

> showWidth :: Int -> Int -> String
> showWidth width n = zeroes ++ num
>     where
>     zeroes = replicate (width - length num) '0'
>     num = show n

> dateToString :: DateStamp -> String
> dateToString (d, m, y) = (showWidth 2 d) ++ "-" ++ (showWidth 2 $ fromEnum m + 1) ++ "-" ++ (showWidth 2 y)

> timeStamp :: ClockTime -> String
> timeStamp ct = let cal = toUTCTime ct in 
>                  (showWidth 2 $ ctHour cal) ++ ":" ++ (showWidth 2 $ ctMin cal) ++ ":" ++ (showWidth 2 $ ctSec cal)

> dateStamp :: ClockTime -> DateStamp
> dateStamp ct = let cal = toUTCTime ct in (ctDay cal, ctMonth cal, ctYear cal)

> logString :: Handle -> String -> LB ()
> logString hdl str = liftIO $ hPutStrLn hdl str

| Callback for when somebody joins. Log it.

> joinCB :: IRC.Message -> ClockTime -> Handle -> History -> LB History
> joinCB msg ct hdl his = do
>                logString hdl $ show new
>                return $ new : his
>     where
>     new  = Joined nick ct
>     nick = IRC.nick msg

| when somebody quits

> quitCB :: IRC.Message -> ClockTime -> Handle -> History -> LB History
> quitCB msg ct hdl his = do
>                logString hdl $ show new
>                return $ new : his
>     where
>     new  = Parted nick ct
>     nick = IRC.nick msg

| when somebody changes his\/her name

> nickCB :: IRC.Message -> ClockTime -> Handle -> History -> LB History
> nickCB msg ct hdl his = do
>                logString hdl $ show new
>                return $ new : his
>     where
>     new  = Renick nick ct newnick
>     nick = IRC.nick msg
>     newnick = drop 1 $ head (msgParams msg)

| When somebody speaks, log it.

> msgCB :: IRC.Message -> ClockTime -> Handle -> History -> LB History
> msgCB msg ct hdl his = do
>                logString hdl $ show new
>                return $ new : his
>     where
>     new  = Said nick ct said
>     nick = IRC.nick msg
>     said = tail . concat . tail $ msgParams msg -- each lines is :foo 

