{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Journal.Parse (parseJournal, printJournal) where

import Control.Lens
import Control.Monad
import Data.Char
import Data.List (intersperse)
import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as TL
import Data.Time
import Data.Void
import Journal.Amount
import Journal.Types
import Text.Megaparsec
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = ParsecT Void Text Identity

-- 2020-06-09 buy 50 AAPL $316.00

skipLineComment' :: Tokens Text -> Parser ()
skipLineComment' prefix =
  string prefix
    *> void (takeWhileP (Just "character") (\x -> x /= '\n' && x /= '\r'))

whiteSpace :: Parser ()
whiteSpace = L.space space1 lineCmnt blockCmnt
  where
    lineCmnt = skipLineComment' "#"
    blockCmnt = L.skipBlockComment "/*" "*/"

lexeme :: Parser a -> Parser a
lexeme p = p <* whiteSpace

keyword :: Text -> Parser Text
keyword = lexeme . string

parseJournal :: Parser [Timed Action]
parseJournal = many (parseTimed parseAction)

parseTimed :: Parser a -> Parser (Timed a)
parseTimed p = do
  _time <- Journal.Parse.parseTime
  _item <- p
  pure Timed {..}

parseAction :: Parser Action
parseAction = do
  kw <- parseKeyword
  case kw of
    "buy" -> Buy <$> parseLot
    "sell" -> Sell <$> parseLot
    "adjust" -> Adjust <$> parseLot
    _ -> error $ "Unexpected action: " ++ TL.unpack kw

parseLot :: Parser Lot
parseLot = do
  _amount <- parseAmount
  _symbol <- TL.toStrict <$> parseSymbol
  _price <- parseAmount
  _details <- many parseAnnotation
  pure Lot {..}

parseAnnotation :: Parser Annotation
parseAnnotation = do
  keyword "fees" *> (Fees <$> parseAmount)
    <|> keyword "commission" *> (Commission <$> parseAmount)
    <|> keyword "gain" *> (Gain <$> parseAmount)
    <|> keyword "loss" *> (Loss <$> parseAmount)
    <|> keyword "washed" *> (Washed <$> parseReason <*> parseAmount)
    <|> keyword "partwashed" *> pure PartWashed
    <|> keyword "position" *> (Position <$> parseEffect)
  where
    parseReason =
      Retroactively <$ keyword "retroactively"
        <|> OnOpen <$ keyword "onOpen"
    parseEffect =
      Open <$ keyword "open"
        <|> Close <$ keyword "close"

printJournal :: [Timed Action] -> Text
printJournal =
  TL.concat
    . intersperse "\n"
    . map (printTimed printAction)

printTimed :: (a -> Text) -> Timed a -> Text
printTimed printItem t =
  TL.concat $ intersperse " " $
    [ printTime (t ^. time),
      printItem (t ^. item)
    ]

printAction :: Action -> Text
printAction = \case
  Buy lot -> "buy " <> printLot lot
  Sell lot -> "sell " <> printLot lot
  Adjust lot -> "adjust " <> printLot lot
  Deposit amt -> "deposit " <> printAmount 2 amt
  Withdraw amt -> "withdraw " <> printAmount 2 amt
  Assign lot -> "assign " <> printLot lot
  Expire lot -> "expire " <> printLot lot
  Dividend lot -> "dividend " <> printLot lot

printLot :: Lot -> Text
printLot lot =
  TL.concat $ intersperse " " $
    [ printAmount 0 (lot ^. amount),
      TL.fromStrict (lot ^. symbol),
      printAmount 4 (lot ^. price)
    ]
      ++ map f (lot ^. details)
  where
    f = \case
      Fees x -> "fees " <> printAmount 2 x
      Commission x -> "commission " <> printAmount 2 x
      Gain x -> "gain " <> printAmount 6 x
      Loss x -> "loss " <> printAmount 6 x
      Washed reason amt -> "wash " <> w reason <> printAmount 6 amt
      PartWashed -> "partWashed"
      Position eff -> case eff of
        Open -> "open"
        Close -> "close"
    w = \case
      Retroactively -> "retroactively"
      OnOpen -> "onOpen"

parseKeyword :: Parser Text
parseKeyword =
  keyword "buy"
    <|> keyword "sell"
    <|> keyword "adjust"
    <|> keyword "deposit"
    <|> keyword "withdraw"
    <|> keyword "assign"
    <|> keyword "expire"
    <|> keyword "dividend"

parseTime :: Parser UTCTime
parseTime = do
  dateString <- some (satisfy (\c -> isDigit c || c == '-')) <* whiteSpace
  timeString <-
    optional (some (satisfy (\c -> isDigit c || c == ':')) <* whiteSpace)
  case timeString of
    Nothing -> parseTimeM False defaultTimeLocale "%Y-%m-%d" dateString
    Just str ->
      parseTimeM
        False
        defaultTimeLocale
        "%Y-%m-%d %H:%M:%S%Q"
        (dateString ++ " " ++ str)

printTime :: UTCTime -> Text
printTime = TL.pack . formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S%Q"

parseAmount :: Parser (Amount 6)
parseAmount =
  read <$> some (satisfy (\c -> isDigit c || c == '.')) <* whiteSpace

printAmount :: Int -> Amount 6 -> Text
printAmount n = TL.pack . amountToString n

parseSymbol :: Parser Text
parseSymbol =
  TL.pack <$> some (satisfy (\c -> isAlphaNum c || c `elem` ['.', '/']))
    <* whiteSpace
