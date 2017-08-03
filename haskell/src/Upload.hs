{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Upload where

import           Network.Wai.Parse

import qualified Data.ByteString.Char8      as BS
import qualified Data.ByteString.Lazy       as B
import           Data.Text                  (Text)
import qualified Data.Text                  as T

import           System.Directory
import           System.FilePath            (takeBaseName, takeExtension, (</>))

import           Control.Exception
import           Control.Monad              (unless)
import           Control.Monad.IO.Class     (liftIO)
import           Control.Monad.Trans.Either
import           Data.Monoid                ((<>))

import           Data.Aeson.Encode          (encode)
import           Kiss
import           ParseCNF
import           Shell

processSet :: (FilePath, B.ByteString) -> EitherT Text IO [KissCell]
processSet t@(fName, fileContents) = do
  tryIO $ B.writeFile ("static/sets" </> fName) fileContents
  staticDir <- createSetDir t
  unzipFile fName staticDir
  createCels t staticDir

createSetDir :: (FilePath, B.ByteString) -> EitherT Text IO FilePath
createSetDir (fName, fileContents) = do
  let staticDir = "static/sets/" <> takeBaseName fName
  let createParents = True
  tryIO $ createDirectoryIfMissing createParents staticDir
  return staticDir

createCels :: (FilePath, B.ByteString) -> FilePath -> EitherT Text IO [KissCell]
createCels (fName, fileContents) staticDir = do
  cnf <- getCNF staticDir
  KissSet kissData celData kissPalette <- getKissSet cnf
  celsWithOffsets <- convertCels kissPalette (map cnfCelName celData) staticDir
  let realCelData = addOffsetsToCelData celsWithOffsets celData
  let json = "var kissJson = " <> encode kissData <> ";\n" <>
             "var celJson = " <> encode realCelData <> ";\n"
  tryIO $ B.writeFile (staticDir <> "/setdata.js") json
  return realCelData

addOffsetsToCelData :: [(String, (Int, Int))] -> [CNFKissCell] ->
                       [KissCell]
addOffsetsToCelData offsets cells =
  [ KissCell cnfCelFix cnfCelName cnfCelPalOffset cnfCelSets cnfCelAlpha (Position xoff yoff)
     | cell@CNFKissCell{..} <- cells, offset@(_, (xoff, yoff)) <- offsets, cnfCelName == fst offset]

tryIO :: IO () -> EitherT Text IO ()
tryIO f = do
  result <-liftIO (try f :: IO (Either IOException ()))
  case result of
    Right () -> return ()
    Left ex  -> EitherT $ return $ Left (T.pack $ show ex)

-- for now, only looks at first cnf listed
getCNF :: FilePath -> EitherT Text IO String
getCNF dir = do
  files <- liftIO $ getDirectoryContents dir
  let cnfs = filter (\x -> takeExtension x == ".cnf") files
  case cnfs of
    (x:_xs)     -> liftIO $ readFile $ dir </> x
    _otherwise -> EitherT $ return $ Left "No configuration file found."
