module Chalmers.QuickCheck.Property where

--------------------------------------------------------------------------
-- imports

import Chalmers.QuickCheck.Gen
import Chalmers.QuickCheck.Arbitrary
import Chalmers.QuickCheck.Text( showErr )
import Chalmers.QuickCheck.Exception

import Control.Concurrent
  ( forkIO
  , threadDelay
  , killThread
  , newEmptyMVar
  , takeMVar
  , putMVar
  )

import Data.IORef

import IO
  ( hFlush
  , stdout
  )

--------------------------------------------------------------------------
-- fixeties

infixr 0 ==>
infixr 1 .&., .&&.

--------------------------------------------------------------------------
-- type Property, Testable

type Property = Gen Prop

class Testable prop where
  property :: prop -> Property

instance Testable () where
  property _ = property rejected

instance Testable Bool where
  property = property . liftBool

instance Testable Result where
  property = return . MkProp . return . return

instance Testable Prop where
  property = return

instance Testable prop => Testable (Gen prop) where
  property mp = do p <- mp; property p

instance (Arbitrary a, Show a, Testable prop) => Testable (a -> prop) where
  property f = forAllShrink arbitrary shrink f

--------------------------------------------------------------------------
-- type Prop

-- is this the right level to be abstract at?

newtype Prop = MkProp{ unProp :: Rose (IO Result) }

-- type Rose

data Rose a = MkRose a [Rose a]

join :: Rose (Rose a) -> Rose a
join (MkRose ~(MkRose x ts) tts) =
  -- first shrinks outer quantification; makes most sense
  MkRose x (map join tts ++ ts)
  -- first shrinks inner quantification
  --MkRose x (ts ++ map join tts)

instance Functor Rose where
  fmap f ~(MkRose x rs) = MkRose (f x) [ fmap f r | r <- rs ]

instance Monad Rose where
  return x = MkRose x []
  m >>= k  = join (fmap k m)

-- type Result

data Result
  = MkResult
  { ok        :: Maybe Bool
  , expect    :: Bool
  , reason    :: String
  , stamp     :: [(String,Int)]
  , callback  :: IO ()
  , callback' :: IO ()
  }

result :: Result
result =
  MkResult
  { ok        = undefined
  , expect    = True
  , reason    = ""
  , stamp     = []
  , callback  = return ()
  , callback' = return ()
  }

failed, succeeded, rejected :: Result
failed        = result{ ok = Just False }
exception err = failed{ reason = "Exception: '" ++ showErr err ++ "'" }
succeeded     = result{ ok = Just True }
rejected      = result{ ok = Nothing }

--------------------------------------------------------------------------
-- lifting and mapping functions

liftBool :: Bool -> Property
liftBool b = liftResult $
  result
  { ok     = Just b
  , reason = if b then "" else "Falsifiable"
  }

liftResult :: Result -> Property
liftResult r = liftIOResult (return r)

liftIOResult :: IO Result -> Property
liftIOResult m = liftRoseIOResult (return (wrap m))
 where
  wrap m = either exception id `fmap` tryEvaluateIO m

liftRoseIOResult :: Rose (IO Result) -> Property
liftRoseIOResult t = return (MkProp t)

mapResult :: Testable prop => (Result -> Result) -> prop -> Property
mapResult f = mapIOResult (>>= wrap f)
 where
  wrap f res =
    do mres <- tryEvaluate res
       return $ f $ case mres of
         Left  err -> exception err
         Right res -> res
       
mapIOResult :: Testable prop => (IO Result -> IO Result) -> prop -> Property
mapIOResult f = mapRoseIOResult (fmap (f . wrap))
 where
  wrap iores =
    do miores <- tryEvaluate iores
       case miores of
         Left err    -> return (exception err)
         Right iores -> iores

mapRoseIOResult :: Testable prop => (Rose (IO Result) -> Rose (IO Result)) -> prop -> Property
mapRoseIOResult f = mapProp (\(MkProp t) -> MkProp (f t))

mapProp :: Testable prop => (Prop -> Prop) -> prop -> Property
mapProp f = fmap f . property 

--------------------------------------------------------------------------
-- property combinators

mapSize :: Testable prop => (Int -> Int) -> prop -> Property
mapSize f p = sized ((`resize` property p) . f)

shrinking :: Testable prop => (a -> [a]) -> a -> (a -> prop) -> Property
shrinking shrink x pf = fmap (MkProp . join . fmap unProp) (promote (props x))
 where
  props x =
    MkRose (property (pf x)) [ props x' | x' <- shrink x ]

whenFail :: Testable prop => IO () -> prop -> Property
whenFail m = mapResult (\res -> res{ callback = m >> callback res })

whenFail' :: Testable prop => IO () -> prop -> Property
whenFail' m = mapResult (\res -> res{ callback' = m >> callback' res })

expectFailure :: Testable prop => prop -> Property
expectFailure = mapResult (\res -> res{ expect = False })

label :: Testable prop => String -> prop -> Property
label s = classify True s

collect :: (Show a, Testable prop) => a -> prop -> Property
collect x = label (show x)

classify :: Testable prop => Bool -> String -> prop -> Property
classify b s = cover b 0 s

cover :: Testable prop => Bool -> Int -> String -> prop -> Property
cover b n s = mapIOResult $ \ior ->
  do eeb <- tryEvaluate b
     res <- ior
     return $
       case eeb of
         Left err    -> res{ ok     = Just False
                           , reason = "Exception: '" ++ showErr err ++ "'"
                           }
         Right True  -> res{ stamp  = (s,n) : stamp res }
         Right False -> res

(==>) :: Testable prop => Bool -> prop -> Property
False ==> _ = property ()
True  ==> p = property p

-- INVESTIGATE: does not work
-- NOTE: n is in microseconds
within :: Testable prop => Int -> prop -> Property
within n = mapIOResult race
 where
  race ior =
    do put "Race starts ..."
       resV <- newEmptyMVar
       pidV <- newEmptyMVar
       partResV <- newIORef failed
       
       let waitAndFail =
             do put "Waiting ..."
                threadDelay n
                put "Done waiting!"
                partRes <- readIORef partResV
                putMVar resV $
                  partRes
                  { ok     = Just False
                  , reason = "Time out"
                  }
           
           evalProp =
             do put "Evaluating Result ..."
                res <- ior
                writeIORef partResV res
                put "Evaluating OK ..."
                mok <- tryEvaluate (ok res == Just False)
                case mok of
                  Left err -> do put "Exception!"
                                 putMVar resV $
                                   res
                                   { ok     = Just False
                                   , reason = "Exception: '" ++ showErr err ++ "'"
                                   } 
                  Right _  -> do put "Done!"
                                 putMVar resV res
       
       -- used "mfix" here before but got non-termination problems
       pid1  <- forkIO $ do pid2 <- takeMVar pidV
                            evalProp
                            killThread pid2
       pid2  <- forkIO $ do waitAndFail
                            killThread pid1
       putMVar pidV pid2

       put "Blocking ..."
       res <- takeMVar resV
       put ("Got Result: " ++ show (ok res))
       return res
         

  put s | True      = do return ()
        | otherwise = do putStrLn s
                         hFlush stdout

{-
-- The following functions should be removed, because:
forThis       x        pf = forAll (return x) pf
forThisShrink x shrink pf = forAllShrink (return x) shrink pf
-}

{-
forThis :: (Show a, Testable prop)
       => a -> (a -> prop) -> Property
forThis x pf =
  whenFail (putStrLn (show x)) $
    property (pf x)

forThisShrink :: (Show a, Testable prop)
       => a -> (a -> [a]) -> (a -> prop) -> Property
forThisShrink x shrink pf =
  shrinking shrink x $ \x' ->
    whenFail (putStrLn (show x')) $
      property (pf x')
-}

forAll :: (Show a, Testable prop)
       => Gen a -> (a -> prop) -> Property
forAll gen pf =
  gen >>= \x ->
    whenFail (putStrLn (show x)) $
      property (pf x)

forAllBlind :: Testable prop => Gen a -> (a -> prop) -> Property
forAllBlind gen pf =
  gen >>= \x ->
    whenFail (putStrLn "(*)") $
      property (pf x)

forAllShrink :: (Show a, Testable prop)
             => Gen a -> (a -> [a]) -> (a -> prop) -> Property
forAllShrink gen shrink pf =
  gen >>= \x ->
    shrinking shrink x $ \x' ->
      whenFail (putStrLn (show x')) $
        property (pf x')

-- experimental
(.&.) :: (Testable prop1, Testable prop2) => prop1 -> prop2 -> Property
p1 .&. p2 =
  arbitrary >>= \b ->
    whenFail (putStrLn (if b then "LHS" else "RHS")) $
      if b then property p1 else property p2

(.&&.) :: (Testable prop1, Testable prop2) => prop1 -> prop2 -> Property
p1 .&&. p2 = error "not implemented yet"

forSeveral :: (Show a, Testable prop) => Gen a -> (a -> prop) -> Property
forSeveral gen pf = forSeveralShrink gen shrinkNothing pf

forSeveralShrink :: (Show a, Testable prop)
                 => Gen a -> (a -> [a]) -> (a -> prop) -> Property
forSeveralShrink gen shrink pf =
  (listOf gen `suchThat` (not . null)) >>= \xs ->
    shrinking shrink' xs $ \xs' ->
      whenFail (print (last xs')) $
        foldr1 (.&&.) [ property (pf x) | x <- xs' ]
 where
  shrink' [x] = [ [x'] | x' <- shrink x ]
  shrink' xs  = [ [x]  | x <- xs ]

--------------------------------------------------------------------------
-- the end.
