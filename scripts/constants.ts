export enum ChainId {
  BSC_TESTNET = 97,
  BSC_MAINNET = 56
}

export const BSC_TESTNET = 97
export const BSC_MAINNET = 56

export const EIGHTEEN_ZEROES = "000000000000000000"
export const SIX_ZEROES = "000000"

export const FEES_WALLET = '0x'
export const INVESTMENT_WALLET = '0x'

export const SUPPORTED_TOKEN_ADDRESS = {
  [ChainId.BSC_TESTNET]: "0x", // TOKEN (deployed by user)
  [ChainId.BSC_MAINNET]: "0x55d398326f99059fF775485246999027B3197955" // BEP20USDT 18 decimals
}

export const DEX_ROUTER = {
  [ChainId.BSC_MAINNET]: "0x10ed43c718714eb63d5aa57b78b54704e256024e",
  [ChainId.BSC_TESTNET]: "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
}