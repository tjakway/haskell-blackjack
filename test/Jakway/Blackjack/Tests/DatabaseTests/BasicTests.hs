module Jakway.Blackjack.Tests.DatabaseTests.BasicTests (tests) where

import Jakway.Blackjack.Tests.DatabaseTests.Common
import System.Directory
import Database.HDBC
import Database.HDBC.Sqlite3
import Database.HDBC.Session (withConnectionIO')
import Test.HUnit
import Control.Monad (liftM, unless)
-- |overlapping for convenience--change if necessary
import qualified Jakway.Blackjack.IO.DatabaseWrites as DB
import qualified Jakway.Blackjack.IO.DatabaseReads as DB
import qualified Jakway.Blackjack.IO.DatabaseCommon as DB
import Jakway.Blackjack.Cards
import Jakway.Blackjack.CardOps
import Control.Monad (when)
import Data.Maybe (fromJust)
import Jakway.Blackjack.Visibility
import Data.List (sort, delete)
import Test.Framework
import Test.Framework.Providers.HUnit
import System.Random
import Control.Monad.State
import Jakway.Blackjack.Game
import Data.Monoid (mempty)

testOpenDatabase :: Assertion
testOpenDatabase = withSingleTableTestDatabase $ (\_ -> do
                                exists <- doesFileExist test_db_name
                                if exists
                                    then return ()
                                    else assertFailure message)
                    where message = "Database "++test_db_name++" does not exist!"

testTableList :: Assertion
testTableList =  withSingleTableTestDatabase $ \conn -> getTables conn >>= (\tables -> unless (tablesEqual tables) (assertFailure $ message tables))
                where tables = ["cards", DB.getPlayerTableName basicTestTableNames, DB.getHandTableName basicTestTableNames, DB.getMatchTableName basicTestTableNames]
                      -- | in case sqlite adds an extra schema table
                      tablesEqual readTables = (sort tables) == (sort . (delete "sqlite_sequence") $ readTables)
                      message readTables = "Database tables don't match!  Read tables: " ++ (show readTables)



testInsertPlayers :: Assertion
testInsertPlayers = withSingleTableTestDatabase $ \conn -> do
                        let numPlayers = 10
                        DB.insertPlayers conn basicTestTableNames numPlayers
                        commit conn
                        numPlayerRows <- DB.getNumPlayers conn basicTestTableNames
                        let message = "numPlayerRows is "++(show numPlayerRows)++" (should be"++(show numPlayers)++")"
                        assertBool message (numPlayers == numPlayerRows) 

testInsertOneHand :: Assertion
testInsertOneHand = withSingleTableTestDatabase $ \conn -> do
       let whichPlayer = 1
       DB.insertPlayers conn basicTestTableNames 2
       let hand = [Hidden (Card Spade Ace), Shown (Card Diamond King)] 
       insertStatement <- DB.insertHandStatement conn basicTestTableNames
       whichHand <- DB.insertHand insertStatement conn basicTestTableNames whichPlayer hand
       commit conn

       readStatement <- DB.readHandStatement conn basicTestTableNames
       res <- DB.readHand readStatement whichHand
       case res of Nothing -> assertFailure "Could not read hand id!"
                   Just resHand -> assertEqual "" hand resHand

testInsertRandStartingHands :: Assertion
testInsertRandStartingHands = withSingleTableTestDatabase $ \conn -> do
       let whichPlayer = 0
       DB.insertPlayers conn basicTestTableNames 2
       commit conn

       --insert between 10 and 100 hands
       numHands <- randomRIO (10, 100)
       gen <- getStdGen
       let startingDeck = infiniteShuffledDeck gen
       
        --don't need the state monad here--use a fold to keep track of state
       let hands= fst $ foldr (\_ (accumulatedHands, thisDeck) -> let (drawnHand, resDeck) = runState startingHand thisDeck
               in (drawnHand : accumulatedHands, resDeck)) (mempty, startingDeck) ([1..numHands] :: [Int])
               -- ^ start with an empty list of hands

       testInsertHands conn whichPlayer hands
       return ()

testInsertThreeCardHand :: Assertion
testInsertThreeCardHand = withSingleTableTestDatabase $ \conn -> do
       let whichPlayer = 0
       DB.insertPlayers conn basicTestTableNames 2
       commit conn

       gen <- getStdGen
       let deck = infiniteShuffledDeck gen
       let hand = return $ flip evalState deck $ do
           firstCard <- drawCard
           secondCard <- drawCard
           thirdCard <- drawCard
           return [Hidden firstCard, Shown secondCard, Hidden thirdCard]

       testInsertHands conn 1 hand
    

testInsertHands :: (IConnection a) => a -> Int -> [Hand] -> Assertion
testInsertHands conn whichPlayer hands
                            | whichPlayer < 0 = assertFailure ("Invalid player id: "++ (show whichPlayer))
                            | hands == [] = assertFailure "Attempted to insert empty list of hands"
                            | otherwise = do
                                -- |insert the ids then read them back from
                                -- the DB
                                insertStatement <- DB.insertHandStatement conn basicTestTableNames
                                --player ids don't really matter here
                                let playerIds = replicate (length hands) whichPlayer
                                handIds <- DB.insertHands insertStatement conn basicTestTableNames (playerIds, hands)
                                commit conn

                                readStatement <- DB.readHandStatement conn basicTestTableNames
                                commit conn
                                res <- sequence $ map (DB.readHand readStatement) handIds
                                --make sure there weren't any problems
                                when (res `elem` Nothing) $ assertFailure "failed to insert a hand!"

                                --unwrap the maybes
                                let readHands = map fromJust res
                                assertBool "Ought to have read the same hands we inserted into the database" ((sort hands) == (sort readHands))


                                

tests =  testGroup "BasicTests" [testCase "testOpenDatabase" testOpenDatabase, testCase "testTableList" testTableList, testCase "testInsertPlayers" testInsertPlayers, testCase "testInsertOneHand" testInsertOneHand, testCase "testInsertRandStartingHands" testInsertRandStartingHands, testCase "testInsertThreeCardHand" testInsertThreeCardHand]
