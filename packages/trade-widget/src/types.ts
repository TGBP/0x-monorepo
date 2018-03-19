import { Order, SignedOrder } from '0x.js';
import * as Web3 from 'web3';

export type ArtifactContractName = 'Forwarder';

export interface Artifact {
    contract_name: ArtifactContractName;
    networks: {
        [networkId: number]: {
            address: string;
            abi: Web3.ContractAbi;
        };
    };
}

export enum AssetToken {
    ZRX = 'ZRX',
    BAT = 'BAT',
}

export enum ActionTypes {
    UpdateNetworkId = 'UPDATE_NETWORK_ID',
    UpdateSelectedToken = 'UPDATE_SELECTED_TOKEN',
    UpdateUserAddress = 'UPDATE_USER_ACCOUNT',
    UpdateUserWeiBalance = 'UPDATE_USER_WEI_BALANCE',
    UpdateOrder = 'UPDATE_ORDER',
    UpdateUserTokenBalance = 'UPDATE_USER_TOKEN_BALANCE',
}
export interface Action {
    type: ActionTypes;
    data?: any;
}

export declare type OrderUpdateCallback = (order: SignedOrder) => any;
export interface LiquidityProvider {
    start(): void;
    stop(): void;
}