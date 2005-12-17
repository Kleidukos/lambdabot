--
-- | 
-- Module    : Fact
-- Copyright : 2003 Shae Erisson
--
-- License:     lGPL
--
-- Quick ugly hack to get factoids in lambdabot.  This is a rewrite of
-- Shae's original code to use internal module states. jlouis
--
module Plugins.Fact (theModule) where

import Lambdabot
import LBState
import Util
import Serial
import qualified Map as M
import qualified Data.FastPackedString as P

------------------------------------------------------------------------

newtype FactModule = FactModule ()

theModule :: MODULE
theModule = MODULE $ FactModule()

type FactState  = M.Map P.FastString P.FastString
type FactWriter = FactState -> LB ()
type Fact m a   = ModuleT FactState m a

instance Module FactModule FactState where

  moduleCmds   _ = ["fact","fact-set","fact-delete"
                   ,"fact-cons","fact-snoc","fact-update"]
  moduleHelp _ s = case s of
    "fact"        -> "@fact <fact>, Retrieve a fact from the database"
    "fact-set"    -> "Define a new fact, guard if exists"
    "fact-update" -> "Define a new fact, overwriting"
    "fact-delete" -> "Delete a fact from the database"
    "fact-cons"   -> "cons information to fact"
    "fact-snoc"   -> "snoc information to fact"
    _             -> "Store and retrieve facts from a database"

  moduleDefState _  = return $ M.empty
  moduleSerialize _ = Just mapPackedSerial

  process _ _ _ cmd rest = do
        result <- withMS $ \factFM writer -> case words rest of
            []         -> return "I can not handle empty facts."
            (fact:dat) -> processCommand factFM writer
                                (P.pack $ lowerCaseString fact) 
                                cmd 
                                (P.pack $ unwords dat)
        return [result]

------------------------------------------------------------------------

processCommand :: FactState -> FactWriter
               -> P.FastString -> String -> P.FastString -> Fact LB String
processCommand factFM writer fact cmd dat = case cmd of
        "fact"        -> return $ getFact factFM fact 
        "fact-set"    -> updateFact True factFM writer fact dat
        "fact-update" -> updateFact False factFM writer fact dat
        "fact-cons"   -> alterFact ((dat `P.append` (P.pack " ")) `P.append`) factFM writer fact
        "fact-snoc"   -> alterFact (P.append ((P.pack " ") `P.append` dat))   factFM writer fact
        "fact-delete" -> writer ( M.delete fact factFM ) >> return "Fact deleted."
        _ -> return "Unknown command."

updateFact :: Bool -> FactState -> FactWriter -> P.FastString -> P.FastString -> Fact LB String
updateFact guard factFM writer fact dat =
    if guard && M.member fact factFM
        then return "Fact already exists, not updating"
        else writer ( M.insert fact dat factFM ) >> return "Fact recorded."

alterFact :: (P.FastString -> P.FastString) 
          -> FactState -> FactWriter -> P.FastString -> Fact LB String
alterFact f factFM writer fact =
    case M.lookup fact factFM of
        Nothing -> return "A fact must exist to alter it"
        Just x  -> do writer $ M.insert fact (f x) factFM
                      return "Fact altered."

getFact :: M.Map P.FastString P.FastString -> P.FastString -> String
getFact fm fact = case M.lookup fact fm of
        Nothing -> "I know nothing about " ++ P.unpack fact
        Just x  -> P.unpack fact ++ ": " ++ P.unpack x
