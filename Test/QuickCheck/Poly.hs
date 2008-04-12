module Test.QuickCheck.Poly
  ( A, B, C
  , OrdA, OrdB, OrdC
  )
 where

--------------------------------------------------------------------------
-- imports

import Test.QuickCheck.Arbitrary

--------------------------------------------------------------------------
-- polymorphic A, B, C (in Eq)

-- A

newtype A = A{ unA :: Int }
  deriving ( Eq )

instance Show A where
  showsPrec n (A x) = showsPrec n x

instance Arbitrary A where
  arbitrary = A `fmap` arbitrary

instance CoArbitrary A where
  coarbitrary = coarbitrary . unA

-- B

newtype B = B{ unB :: Int }
  deriving ( Eq )

instance Show B where
  showsPrec n (B x) = showsPrec n x

instance Arbitrary B where
  arbitrary = B `fmap` arbitrary

instance CoArbitrary B where
  coarbitrary = coarbitrary . unB

-- C

newtype C = C{ unC :: Int }
  deriving ( Eq )

instance Show C where
  showsPrec n (C x) = showsPrec n x

instance Arbitrary C where
  arbitrary = C `fmap` arbitrary

instance CoArbitrary C where
  coarbitrary = coarbitrary . unC

--------------------------------------------------------------------------
-- polymorphic OrdA, OrdB, OrdC (in Eq, Ord)

-- OrdA

newtype OrdA = OrdA{ unOrdA :: Int }
  deriving ( Eq, Ord )

instance Show OrdA where
  showsPrec n (OrdA x) = showsPrec n x

instance Arbitrary OrdA where
  arbitrary = OrdA `fmap` arbitrary

instance CoArbitrary OrdA where
  coarbitrary = coarbitrary . unOrdA

-- OrdB

newtype OrdB = OrdB{ unOrdB :: Int }
  deriving ( Eq, Ord )

instance Show OrdB where
  showsPrec n (OrdB x) = showsPrec n x

instance Arbitrary OrdB where
  arbitrary = OrdB `fmap` arbitrary

instance CoArbitrary OrdB where
  coarbitrary = coarbitrary . unOrdB

-- OrdC

newtype OrdC = OrdC{ unOrdC :: Int }
  deriving ( Eq, Ord )

instance Show OrdC where
  showsPrec n (OrdC x) = showsPrec n x

instance Arbitrary OrdC where
  arbitrary = OrdC `fmap` arbitrary

instance CoArbitrary OrdC where
  coarbitrary = coarbitrary . unOrdC

--------------------------------------------------------------------------
-- the end.

