{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE LambdaCase #-}


import Paths_hylogen (getDataFileName)
import Control.Monad
import Control.Concurrent
import qualified Data.ByteString.Char8 as BS8
import Data.ByteString (ByteString)
import Network (PortID(..), withSocketsDo, listenOn)
import Network.Socket (accept, sClose)
import Network.Socket.ByteString (sendAll)

-- import Data.Monoid
import qualified Data.Text as T
import Network.WebSockets
import System.Environment (getArgs)
import System.FilePath
import System.FSNotify
import System.Process

-- import System.Random

main :: IO ()
main = getArgs >>= \case
  [pathToWatch] -> main' pathToWatch
  _ -> error "Name a file to watch!"

main' :: FilePath ->  IO ()
main' pathToWatch = withManager $ \mgr -> do
  _ <- forkIO $ serveIndex
  runServer "127.0.0.1" 8080 $ handleConnection pathToWatch mgr

handleConnection :: FilePath -> WatchManager -> PendingConnection -> IO ()
handleConnection pathToWatch mgr pending = do
   let (dirToWatch, fileToWatch) = splitFileName pathToWatch
   connection <- acceptRequest pending

   (sendTextData connection . T.pack) =<< getNewSource pathToWatch

   let onChange e = case e of
         Modified _ _ -> (sendTextData connection . T.pack) =<< getNewSource pathToWatch
         _ -> return ()
   _ <- watchDir mgr dirToWatch (const True) onChange
   _ <- getLine -- temp hack to keep the socket open
   return ()

getNewSource :: FilePath -> IO String
getNewSource pathToWatch = do
   -- TODO: more robust paths!:
   -- c <- readFile pathToWatch
   let (dirToWatch, fileToWatch) = splitFileName pathToWatch
   c <- readProcess "runghc" [
        "-i"++dirToWatch
      , pathToWatch
      ] ""
   putStrLn "updated"
   return c

serveIndex :: IO ()
serveIndex = withSocketsDo $ do
   htmlString <- readFile =<< getDataFileName "app/index.html"
   sock <- listenOn $ PortNumber 5678
   forever $ do
      (conn, _) <- accept sock
      _ <- forkIO $ do
         sendAll conn $ wrapHtml $ BS8.pack htmlString
         sClose conn
      return ()

wrapHtml :: ByteString -> ByteString
wrapHtml bs = mconcat [
     "HTTP/1.0 200 OK\r\nContent-Length: "
   , BS8.pack . show $ BS8.length bs
   , "\r\n\r\n", bs, "\r\n"
   ]


