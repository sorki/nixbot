{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NamedFieldPuns    #-}
{-# LANGUAGE OverloadedStrings #-}

module Config (
    getConfig
  , amqpOptions
  , Config(..)
  , PluginConfig(..)
  , CommandsConfig(..)
  , enableCommands
  , pluginConfigForSender
  ) where

import           Data.Aeson
import qualified Data.ByteString.Lazy.Char8 as BS
import           Data.Char                  (toLower)
import           Data.List                  (stripPrefix)
import           Data.Maybe                 (fromMaybe)
import           Data.Map                   (Map)
import qualified Data.Map                   as Map
import           Data.Text                  (Text)
import           GHC.Generics               (Generic)
import           Network.AMQP
import           Options.Applicative
import           System.Directory           (makeAbsolute)

parser :: Parser FilePath
parser = argument str
         ( metavar "FILE"
        <> help "Config file" )

opts :: ParserInfo FilePath
opts = info (parser <**> helper)
   ( fullDesc
  <> progDesc "Hnixbot"
  <> header "hnixbot - hnix bot"
   )

lowerFirst :: String -> String
lowerFirst []       = []
lowerFirst (c:rest) = toLower c : rest

customOptions :: Options
customOptions = defaultOptions
  { fieldLabelModifier = \field ->
      lowerFirst .
      fromMaybe (error $ "field " ++ field ++ " in Config.hs not prefixed with \"config\"") .
      stripPrefix "config" $
      field
  }

data CommandsConfig = CommandsConfig
  { configEnable   :: Bool
  } deriving (Show, Generic)

instance FromJSON CommandsConfig where
  parseJSON = genericParseJSON customOptions

enableCommands :: PluginConfig -> Bool
enableCommands PluginConfig { configCommands = CommandsConfig { configEnable } } = configEnable

data PluginConfig = PluginConfig
  { configCommands :: CommandsConfig
  } deriving (Show, Generic)

instance FromJSON PluginConfig where
  parseJSON = genericParseJSON customOptions


data Config = Config
  { configUser            :: Text
  , configPassword        :: Text
  , configDebugMode       :: Bool
  , configChannelDefaults :: PluginConfig
  , configUsers           :: PluginConfig
  , configStateDir        :: FilePath
  , configChannels        :: Map Text PluginConfig
  } deriving (Show, Generic)

instance FromJSON Config where
  parseJSON = genericParseJSON customOptions

pluginConfigForSender :: Either Text (Text, Text) -> Config -> PluginConfig
pluginConfigForSender (Left _) = configUsers
pluginConfigForSender (Right (chan, _)) = pluginConfigForChannel chan
  where pluginConfigForChannel channel Config { configChannels, configChannelDefaults } =
          Map.findWithDefault configChannelDefaults channel configChannels

amqpOptions :: Config -> ConnectionOpts
amqpOptions Config { configUser, configPassword } = defaultConnectionOpts
  { coVHost = "ircbot"
  , coTLSSettings = Just TLSTrusted
  , coServers = [("events.nix.gsc.io", 5671)]
  , coAuth = [ amqplain configUser configPassword ]
  }

getConfig :: IO Config
getConfig = do
  configFile <- execParser opts >>= makeAbsolute >>= BS.readFile

  either fail return $ eitherDecode' configFile
