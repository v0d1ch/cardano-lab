module Cardano.Hydra where

import Cardano.Api (SlotNo)
import Cardano.Prelude hiding (getContents)
import Cardano.Util (HydraNodeArguments (..), checkProcessHasFinished, networkIdToArg, queryTipSlotNo)
import GHC.IO.Handle (hGetLine)
import System.Process (CreateProcess (std_err, std_out), StdStream (..), proc, withCreateProcess)

runHydra :: HydraNodeArguments -> IO ()
runHydra HydraNodeArguments{hnNetworkId, hnNodeSocket} = do
  generateCardanoKeys
  generateHydraKey
  publishHydraScripts
  let hydraProc = proc "hydra-node" runHydraCmd
  withCreateProcess hydraProc{std_out = Inherit, std_err = Inherit} $
    \_stdin mout _stderr processHandle ->
      race_
        (checkProcessHasFinished "hydra-node" processHandle)
        (outputLines mout)
 where
  runHydraCmd =
    [ "--node-id"
    , "cardano-lab-node-1"
    , "--ledger-protocol-parameters"
    , "cardano-lab/config/protocol-parameters.json"
    , "--node-socket"
    , hnNodeSocket
    ]
      <> networkIdToArg hnNetworkId

waitOnSlotNumber :: HydraNodeArguments -> SlotNo -> IO () -> IO ()
waitOnSlotNumber hydraNodeArgs slotNo action = do
  eSlotNo <- try $ queryTipSlotNo hydraNodeArgs
  case eSlotNo of
    -- TODO: distinguish real error from cardano-node just syncing
    Left (_err :: SomeException) -> putTextLn "Waiting on cardano-node socket..." >> tryAgain
    Right slotNo' ->
      if slotNo' >= slotNo
        then action
        else do
          putTextLn ("Waiting on slot " <> show slotNo <> " currently at " <> show slotNo')
          tryAgain
 where
  tryAgain =
    threadDelay 3000000
      >> waitOnSlotNumber hydraNodeArgs slotNo action

generateHydraKey :: IO ()
generateHydraKey = do
  let hydraProc = proc "hydra-node" runHydraCmd
  withCreateProcess hydraProc{std_out = Inherit, std_err = Inherit} $
    \_stdin mout _stderr processHandle ->
      race_
        (checkProcessHasFinished "hydra-node" processHandle)
        (outputLines mout)
 where
  runHydraCmd =
    [ "gen-hydra-key"
    , "--output-file"
    , "hydra"
    ]

publishHydraScripts :: IO ()
publishHydraScripts = do
  let hydraProc = proc "hydra-node" runHydraCmd
  withCreateProcess hydraProc{std_out = Inherit, std_err = Inherit} $
    \_stdin mout _stderr processHandle ->
      race_
        (checkProcessHasFinished "hydra-node" processHandle)
        (outputLines mout)
 where
  runHydraCmd =
    [ "publish-scripts"
    , "--node-socket"
    , "db/node.socket"
    , "--cardano-signing-key"
    , "cardano.sk"
    , "--testnet-magic"
    , "1"
    ]

-- fundFromFaucet :: NetworkId -> String -> IO ()
-- fundFromFaucet networkId address = undefined

-- https://faucet.preprod.world.dev.cardano.org/send-money/address?api_key=ooseiteiquo7Wie9oochooyiequi4ooc
-- curl -X POST -s "https://faucet.preview.world.dev.cardano.org/send-money/address?api_key=nohnuXahthoghaeNoht9Aow3ze4quohc"
generateCardanoKeys :: IO ()
generateCardanoKeys = do
  let hydraProc = proc "cardano-cli" runCardanoCliCmd
  withCreateProcess hydraProc{std_out = Inherit, std_err = Inherit} $
    \_stdin mout _stderr processHandle ->
      race_
        (checkProcessHasFinished "cardano-cli" processHandle)
        (outputLines mout)
 where
  runCardanoCliCmd =
    [ "address"
    , "key-gen"
    , "--signing-key-file"
    , "cardano.sk"
    , "--verification-key-file"
    , "cardano.vk"
    ]

outputLines :: Maybe Handle -> IO ()
outputLines mout = do
  let delaySeconds :: Int = 2
  out <- waitForHandle delaySeconds mout
  processLines out

waitForHandle :: Num t => t -> Maybe b -> IO b
waitForHandle n mhandle =
  case mhandle of
    Nothing -> do
      threadDelay 1000000
      waitForHandle (n - 1) mhandle
    Just out ->
      pure out

processLines :: Handle -> IO ()
processLines out = do
  line <- hGetLine out
  putStrLn line
