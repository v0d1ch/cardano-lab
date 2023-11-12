{-# LANGUAGE TemplateHaskell #-}

module Cardano.Node where

import Cardano.Api (
  ConsensusModeParams (CardanoModeParams),
  EpochSlots (EpochSlots),
  File (File),
  LocalChainSyncClient (..),
  LocalNodeClientProtocols (
    LocalNodeClientProtocols,
    localChainSyncClient,
    localStateQueryClient,
    localTxMonitoringClient,
    localTxSubmissionClient
  ),
  LocalNodeConnectInfo (
    LocalNodeConnectInfo,
    localConsensusModeParams,
    localNodeNetworkId,
    localNodeSocketPath
  ),
  NetworkId (Mainnet, Testnet),
  NetworkMagic (NetworkMagic),
  connectToLocalNode,
 )
import Cardano.Prelude
import Cardano.Util (NodeArguments (..), NodeSocket, checkProcessHasFinished, waitForSocket)
import Katip
import System.Directory (doesFileExist, getCurrentDirectory, removeFile)
import System.FilePath ((</>))
import System.Process (CreateProcess (..), StdStream (..), proc, withCreateProcess)
import Prelude (error)

data NodeHandle a = NodeHandle
  { startNode :: IO (Async a)
  , stopNode :: Async a -> IO ()
  }

data AvailableNetworks
  = Preview
  | Preprod
  | Mainnet
  deriving (Eq, Show, Read)

type Port = Int

-- | Arguments given to the 'cardano-node' command-line to run a node.
data CardanoNodeArgs = CardanoNodeArgs
  { nodeSocket :: NodeSocket
  , nodeConfigFile :: FilePath
  , nodeByronGenesisFile :: FilePath
  , nodeShelleyGenesisFile :: FilePath
  , nodeAlonzoGenesisFile :: FilePath
  , nodeTopologyFile :: FilePath
  , nodeDatabaseDir :: FilePath
  , nodeDlgCertFile :: Maybe FilePath
  , nodeSignKeyFile :: Maybe FilePath
  , nodeOpCertFile :: Maybe FilePath
  , nodeKesKeyFile :: Maybe FilePath
  , nodeVrfKeyFile :: Maybe FilePath
  , nodePort :: Maybe Port
  }

runCardanoNode :: KatipContext m => NodeArguments -> m ()
runCardanoNode = withCardanoNode

withCardanoNode ::
  KatipContext m =>
  NodeArguments ->
  m ()
withCardanoNode NodeArguments{naNetworkId, naNodeSocket} = do
  $(logTM) InfoS "Starting cardano-node"
  p <- liftIO process
  liftIO $
    withCreateProcess p{std_out = Inherit, std_err = Inherit} $
      \_stdin _stdout _stderr processHandle ->
        ( race
            (checkProcessHasFinished "cardano-node" processHandle)
            waitForNode
            >>= \case
              Left{} -> error "never should have been reached"
              Right a -> pure a
        )
          `finally` cleanupSocketFile
 where
  process = do
    cwd <- getCurrentDirectory
    pure $
      cardanoNodeProcess
        (Just "db")
        (defaultCardanoNodeArgs $ networkIdToNodeConfigPath cwd naNetworkId)
  waitForNode = do
    waitForSocket naNodeSocket
    pure ()

  cleanupSocketFile =
    whenM (doesFileExist naNodeSocket) $
      removeFile naNodeSocket

networkIdToNodeConfigPath :: FilePath -> NetworkId -> FilePath
networkIdToNodeConfigPath cwd network =
  let basePath = cwd </> "cardano-lab" </> "config" </> "cardano-configurations" </> "network"
   in case network of
        Cardano.Api.Mainnet -> basePath </> "mainnet" </> "cardano-node"
        Testnet (NetworkMagic 1) -> basePath </> "preprod" </> "cardano-node"
        Testnet (NetworkMagic 2) -> basePath </> "preview" </> "cardano-node"
        Testnet (NetworkMagic 1097911063) -> basePath </> "testnet" </> "cardano-node"
        _ -> error "TODO: implement running on devnet"

defaultCardanoNodeArgs :: FilePath -> CardanoNodeArgs
defaultCardanoNodeArgs nodeConfigPath =
  CardanoNodeArgs
    { nodeSocket = "node.socket"
    , nodeConfigFile = nodeConfigPath </> "config.json"
    , nodeByronGenesisFile = "genesis-byron.json"
    , nodeShelleyGenesisFile = "genesis-shelley.json"
    , nodeAlonzoGenesisFile = "genesis-alonzo.json"
    , nodeTopologyFile = nodeConfigPath </> "topology.json"
    , nodeDatabaseDir = "db"
    , nodeDlgCertFile = Nothing
    , nodeSignKeyFile = Nothing
    , nodeOpCertFile = Nothing
    , nodeKesKeyFile = Nothing
    , nodeVrfKeyFile = Nothing
    , nodePort = Nothing
    }

-- | Generate command-line arguments for launching @cardano-node@.
cardanoNodeProcess :: Maybe FilePath -> CardanoNodeArgs -> CreateProcess
cardanoNodeProcess cwd args =
  (proc "cardano-node" strArgs){cwd}
 where
  CardanoNodeArgs
    { nodeConfigFile
    , nodeTopologyFile
    , nodeDatabaseDir
    , nodeSocket
    , nodePort
    , nodeSignKeyFile
    , nodeDlgCertFile
    , nodeOpCertFile
    , nodeKesKeyFile
    , nodeVrfKeyFile
    } = args

  strArgs =
    "run"
      : mconcat
        [ ["--config", nodeConfigFile]
        , ["--topology", nodeTopologyFile]
        , ["--database-path", nodeDatabaseDir]
        , ["--socket-path", nodeSocket]
        , opt "--port" (show <$> nodePort)
        , opt "--byron-signing-key" nodeSignKeyFile
        , opt "--byron-delegation-certificate" nodeDlgCertFile
        , opt "--shelley-operational-certificate" nodeOpCertFile
        , opt "--shelley-kes-key" nodeKesKeyFile
        , opt "--shelley-vrf-key" nodeVrfKeyFile
        ]

  opt :: a -> Maybe a -> [a]
  opt arg = \case
    Nothing -> []
    Just val -> [arg, val]

connectCardanoNode :: MonadIO m => NetworkId -> NodeSocket -> m ()
connectCardanoNode networkId nodeSocket =
  liftIO $ connectToLocalNode connectInfo clientProtocols
 where
  connectInfo =
    LocalNodeConnectInfo
      { localConsensusModeParams = CardanoModeParams (EpochSlots 21600)
      , localNodeNetworkId = networkId
      , localNodeSocketPath = File nodeSocket
      }

  clientProtocols =
    LocalNodeClientProtocols
      { localChainSyncClient = NoLocalChainSyncClient
      , localTxSubmissionClient = Nothing
      , localStateQueryClient = Nothing
      , localTxMonitoringClient = Nothing
      }
