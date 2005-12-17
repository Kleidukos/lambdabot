--
-- | Simple template module
--
module Plugins.Dummy (theModule) where

import Lambdabot
import LBState
import Util
import Plugins.Dummy.DocAssocs (docAssocs)
import Plugins.Dummy.Moo (cows)
import qualified Map as M
import qualified Data.FastPackedString as P

newtype DummyModule = DummyModule ()

theModule :: MODULE
theModule = MODULE $ DummyModule ()

instance Module DummyModule [String] where
  moduleDefState _ = return $ cycle cows

  moduleCmds   _ = "moo" : map fst dummylst
  moduleHelp _ s = case s of
        "dummy"       -> "print a string constant"
        "wiki"        -> "wiki urls"
        "paste"       -> "paste page url"
        "docs"        -> "@docs <lib>, lookup the url for this library's documentation"
        "libsrc"      -> "@libsrc <lib>, lookup the url for the darcs source for a library"
        "learn"       -> "another url"
        "eurohaskell" -> "urls are good"
        "moo"         -> "vegan-friendly command"
        "map"         -> "#haskell user map"
        "botsnack"    -> "bot-feeder"
        "get-shapr"   -> "summon shapr instantly"
        _             -> "dummy module"

  process _ _ _ "moo" _ = do
        cow' <- withMS $ \(cow:farm) writer -> writer farm >> return cow
        return (lines cow')

  process _ _ _ cmd rest = case lookup cmd dummylst of
       Nothing -> error "Dummy: invalid command"
       Just f  -> return $ lines $ f rest

dummylst :: [(String, String -> String)]
dummylst = [("dummy",       \_ -> "dummy"),
            ("get-shapr",   \_ -> "shapr!!"),
            ("eurohaskell", \_ -> unlines ["less talks, more code!",
                                           "http://www.haskell.org/hawiki/EuroHaskell",
                                           "EuroHaskell - Haskell Hackfest - Summer 2005 ",
                                                "- Gothenburg, Sweden"]),
            ("wiki",        \x -> "http://www.haskell.org/hawiki/" ++ x),
            ("paste",       \_ -> "http://www.haskell.org/hawiki/HaskellIrcPastePage"),
            ("docs",        \x -> case x of
               [] -> "http://haskell.org/ghc/docs/latest/html/libraries/index.html"
               _  -> case M.lookup (P.pack x) docAssocs of
                     Nothing -> x ++ " not available"
                     Just m  -> "http://haskell.org/ghc/docs/latest/html/libraries/" <>
                                (P.unpack m) </> map (choice (=='.') (const '-') id) x <.> "html"),
            ("libsrc",      \x -> case M.lookup (P.pack x) docAssocs of
               Nothing -> x ++ " not available"
               Just m  -> "http://darcs.complete.org/fptools/libraries/" <>
                          (P.unpack m) </> map (choice (=='.') (const '/') id) x <.> "hs"),
            ("learn",       \_ -> "http://www.haskell.org/learning.html"),
            ("map",       \_ -> "http://www.haskell.org/hawiki/HaskellUserLocations"),

            ("botsnack",    \_ -> ":)")]

{-# INLINE choice #-}
choice :: (r -> Bool) -> (r -> a) -> (r -> a) -> (r -> a)
choice p f g x = if p x then f x else g x
-- Generalizations:
-- choice :: ArrowChoice (~>) => r ~> Bool -> r ~> a -> r ~> a -> r ~> a
-- choice :: Monad m => m Bool -> m a -> m a -> m a
