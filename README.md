# Chain Signatures Signer

Solidity Contract to Support [NEAR Chain Signatures](https://docs.near.org/concepts/abstraction/chain-signatures) on AURORA.

What is the main thing this contract does? 

- It calls the MPC service on NEAR and [signs your payload](https://explorer.mainnet.aurora.dev/tx/0x019fbf6ee6aad1edf9c68ab6cc04b8eba16479a724a1d6a9c741c5d04849c3cd).
- Then it propagates [the response](https://explorer.mainnet.aurora.dev/tx/0xf5de2f24cd6d9f7d93e40df638c47bc07c25d014190da4f033a676ed96186b8e?tab=logs) back to the EVM.

This contract opens you the doors to:
-  to create a runtime environment on networks without smart contracts, like Bitcoin, Ripple by using Solidity smart contracts deployed to AURORA
- use Chain Signatures from AURORA directly, using Solidity

This repo uses Foundry. Please install it to deploy/verify your own contract if needed.

Right now we have two such signers deployed:
- [Mainnet CS Signer](https://explorer.mainnet.aurora.dev/address/0xF7607CD922804DaA9D54d21349Dd6F9467098dDE)
- [Testnet CS Signer](https://explorer.testnet.aurora.dev/address/0x7e4F22F1eE20e01719ff1D986D116B04aBB2EE3f)

You can use these or deploy your own one.

## How it works? 

The contract works by using the XCC to communicate with NEAR via its subaccount. You can read more about it in the [XCC Docs](https://doc.aurora.dev/xcc/aurora-to-near/introduction).

## Deploying and verifying

First of all, you will need to put `$PRIVATE_KEY` into your `.env` file and install Foundry.

After that you can just execute, if on Mainnet:

```bash
forge create --rpc-url https://mainnet.aurora.dev ChainSignaturesSigner --legacy --private-key $PRIVATE_KEY --libraries 'lib/xcc/AuroraSdk.sol:AuroraSdk:0x05ADbA73a00b70D2e35BE8F0b44e8Ca6891d925C' --constructor-args v1.signer 0xC42C30aC6Cc15faC9bD938618BcaA1a1FaE8501d
```

And if on Testnet: 
```bash
forge create --rpc-url https://testnet.aurora.dev ChainSignaturesSigner --legacy --private-key $PRIVATE_KEY --libraries 'lib/xcc/AuroraSdk.sol:AuroraSdk:0xa1c283ed4CD8Ddc8694c209B18Fb40f7B3929361' --constructor-args v1.signer-prod.testnet 0x4861825E75ab14553E5aF711EbbE6873d369d146       
```

To verify contract use:

```bash
forge verify-contract --rpc-url https://mainnet.aurora.dev 
<YOUR_CONTRACT_ADDRESS_HERE> ChainSignaturesSigner --verifier blockscout --verifier-url https://explorer.mainnet.aurora.dev/api --libraries 'lib/xcc/AuroraSdk.sol:AuroraSdk:0x05ADbA73a00b70D2e35BE8F0b44e8Ca6891d925C' --guess-constructor-args
```

For the verification on Testnet, just change the rpc, the explorer endpoint, and AuroraSdk library address. Take them from the create command above.

## Initializing the contract

To start using your freshly deployed contract, you will need to initialize it by calling `init` function. To do this:

- Verify the contract
- Approve the wNEAR for the CS Signer (2 wNEAR is needed to init, but I advice you to approve more – to make the `sign` calls in the future, I was using 3 wNEAR).
- Go to the Explorer and call `init` method.

If you forgot smth, you will see crazy gas estimates in your wallet. Usually it is happening because you haven't approved wNEAR for the contract address.

Only the deployer of the contract can call the `init` method.

The method itself looks like that:

```solidity
    function init() public onlyRole(OWNER_ROLE) {
        // Make a cross-contract call to trigger sub-account creation.
        bytes memory data = abi.encodePacked('{\"greeting\":\"Hello from Signer!\"}');
        PromiseCreateArgs memory initCall = near.call("hello.near-examples.testnet", "set_greeting", data, 0, SET_GREETING_NEAR_GAS);
        initCall.transact();
    }
```
It call the simplest possible contract on NEAR to bootstrap itself and initialize the XCC subaccount.

## Signing the payload 

It is done via `sign` function call and recieving the response in the `signCallback` transaction.

To call `sign` you will need to provide:

- `payload` - the data to be signed
- `version` - `key_version` from chain signatures, check NEAR docs. At the moment, it is just 0.
- `attachedNear` - the amount of wNEAR to attach to the NEAR call. Usually 1yoctoNEAR is enough, so you should just enter 1.

The code for the `sign` method looks like this:
```solidity
    function sign(string memory payload, uint256 version, uint128 attachedNear) public {
        bytes memory _data = hexStringToBytes(payload);
        require(_data.length == 32, "Payload must be 32 bytes");

        // path is fixed here to make sure only msg.sender can use the derived 
        // address via chain signature's of the xcc sub-account
        string memory path = addressToString(msg.sender);
        bytes memory data = createData(_data, path, version);

        PromiseCreateArgs memory callSign = near.call(signer, "sign", data, attachedNear,  SIGN_NEAR_GAS);
        PromiseCreateArgs memory callback = near.auroraCall(address(this), abi.encodeWithSelector(this.signCallback.selector), 0, SIGN_CALLBACK_NEAR_GAS);

        callSign.then(callback).transact();
    }
```

The main moments in it to focus onto are:
-  **Ownership Preservation**: The derivation path is equal to `addressToString(msg.sender);` which ensures that only the EOA or contract who is `msg.sender` can operate the derived account on other networks.
- **Callback is optional**: you can remove it and index the NEAR blockchain instead for the MPC response. It will save you some gas if you don't need the signed message back into your Solidity contracts.
- **Gas for signature**: `SIGN_NEAR_GAS` value can change in the future and be optimized. Right now it is 50TGas.

Function `signCallback` just propagates the MPC response back inside EVM and emits `SignedEvent`:
```solidity
    function signCallback() public onlyRole(CALLBACK_ROLE) {
        PromiseResult memory result = AuroraSdk.promiseResult(0);

        if (result.status != PromiseResultStatus.Successful) {
            revert("SignCallback failed");
        }

        string memory output = string(result.output);
        emit SignedEvent(output);
    }
```

The output will contain the `affine_point` and `scalar` to reconstruct the signature. You can do it with:

- [Near Multichain Examples](https://github.com/near-examples/near-multichain/tree/main).
- [Chain Signatures JS](https://github.com/aurora-is-near/chain-signatures-js/tree/main) - only for Bitcoin for now.

## Outro

That is it. Feel free to contact me in Telegram if you will need more support or have any questions – @dhilbert or on Aurora Discord (@slava).

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
