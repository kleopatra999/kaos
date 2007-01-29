module Kaos.VirtRegister (VirtRegister(..), VRegAllocT, runVRegAllocT, newVReg) where

import Kaos.SeqT
import Control.Monad.Trans
import Control.Monad.State
import Data.Generics

newtype VirtRegister = VR Int
    deriving (Show, Read, Eq, Ord, Enum, Data, Typeable)

newtype VRegAllocT m a = RT (SeqT VirtRegister m a)
    deriving (Monad, MonadTrans)

instance (MonadState s m) => MonadState s (VRegAllocT m) where
    get = lift get
    put = lift . put

runVRegAllocT :: (Monad m) => VRegAllocT m a -> m a
runVRegAllocT (RT m ) = runSeqT (VR 0) m

newVReg :: (Monad m) => VRegAllocT m VirtRegister
newVReg = RT getNext
