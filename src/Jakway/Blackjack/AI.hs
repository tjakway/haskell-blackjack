module Jakway.Blackjack.AI where

import Jakway.Blackjack.Visibility
import Jakway.Blackjack.CardOps
import Jakway.Blackjack.Cards
import Jakway.Blackjack.Points
import Control.Monad.State
import System.Random

data AI = BasicDealer | BasicPlayer | FiftyFiftyPlayer
        deriving (Show, Read, Eq)

play :: AI -> Hand -> Deck -> (Hand, Deck)
play BasicDealer myHand deck = flip runState deck $ do
    let points = handPoints (map unwrapVisibility myHand)
    if points < 17
        then do
        drawnCard <- drawCard
        deck' <- get
        return . fst $ play BasicDealer (Shown drawnCard : myHand) deck'
        else 
        return myHand

-- |currently all players play the same
play BasicPlayer myHand deck = play BasicDealer myHand deck
play FiftyFiftyPlayer myHand deck = if isBust $ map unwrapVisibility myHand 
                                        then stand myHand deck
                                        else fiftyfifty deck (hit FiftyFiftyPlayer myHand deck) (stand myHand deck)
        where points = handPoints (map unwrapVisibility myHand)
              --uses the deck as a source of randomness
              --has a 50% chance of calling f, 50% chance of calling 
              fiftyfifty deck f g = let randFlag = fst . random . deckToRNG $ deck
                                            in if randFlag == True then f
                                                                   else g


hit :: AI -> Hand -> Deck -> (Hand, Deck)
hit ai hand deck = flip runState deck $ do
    drawnCard <- drawCard
    deck' <- get
    let newHand = (Shown drawnCard : hand)
    return . fst $ play ai (Shown drawnCard : hand) deck'

stand :: Hand -> Deck -> (Hand, Deck)
stand = (,)

deckToRNG :: Deck -> StdGen
--draw a card from the deck at an arbitrary position and use it to seed a RNG
--the randomness comes from the fact that the deck is shuffled
deckToRNG deck = let (Card suit cardVal) = deck !! position
                     --add 1 in case either value is 0
                     in mkStdGen $ ((fromEnum suit) + 1) * ((fromEnum cardVal) + 1)
        where position = 13
