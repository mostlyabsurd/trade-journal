{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Journal.Entry.Options where

import Amount
import Control.Applicative
import Control.Lens
import Data.Sum.Lens
import qualified Data.Text.Lazy as TL
import GHC.Generics hiding (to)
import Journal.Parse
import Journal.Print
import Journal.Types.Entry
import Journal.Types.Lot
import Text.Show.Pretty
import Prelude hiding (Double, Float)

-- | An Event represents "internal events" that occur within an account,
--   either directly due to the actions above, or indirectly because of other
--   factors.
data Options
  = Exercise Lot -- exercise a long options position
  | Assign Lot -- assignment of a short options position
  | Expire Lot -- expiration of a short options position
  deriving
    ( Show,
      PrettyVal,
      Eq,
      Generic
    )

makePrisms ''Options

_OptionsLot :: Traversal' Options Lot
_OptionsLot f = \case
  Exercise lot -> Exercise <$> f lot
  Assign lot -> Assign <$> f lot
  Expire lot -> Expire <$> f lot

instance HasLot (Const Options) where
  _Lot f (Const s) = fmap Const $ s & _OptionsLot %%~ f

_OptionsNetAmount :: Fold Options (Amount 2)
_OptionsNetAmount f =
  error "impossible" . f . \case
    Exercise _lot -> 0 -- jww (2021-06-12): NYI
    Assign _lot -> 0 -- jww (2021-06-12): NYI
    Expire _lot -> 0

instance HasNetAmount (Const Options) where
  _NetAmount f (Const s) = fmap Const $ s & _OptionsNetAmount %%~ f

printOptions :: Options -> TL.Text
printOptions = \case
  Exercise lot -> "exercise " <> printLot lot
  Assign lot -> "assign " <> printLot lot
  Expire lot -> "expire " <> printLot lot

instance Printable (Const Options) where
  printItem = printOptions . getConst

parseOptions :: Parser Options
parseOptions =
  keyword "exercise" *> (Exercise <$> parseLot)
    <|> keyword "assign" *> (Assign <$> parseLot)
    <|> keyword "expire" *> (Expire <$> parseLot)

instance Producible Parser (Const Options) where
  produce = fmap Const parseOptions
