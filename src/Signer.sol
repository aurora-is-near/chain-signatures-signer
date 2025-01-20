// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.27;

import {
    AuroraSdk,
    NEAR,
    PromiseCreateArgs,
    PromiseResult,
    PromiseResultStatus,
    PromiseWithCallback
} from "./AuroraSdk.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

uint64 constant SIGN_NEAR_GAS = 50_000_000_000_000; // 50 Tgas
uint64 constant SIGN_CALLBACK_NEAR_GAS = 30_000_000_000_000; // 30 Tgas
uint128 constant ATACH_DEPOSIT = 200_000_000_000_000_000_000_000; // 0.2 NEAR

contract Signer {
    using AuroraSdk for NEAR;
    using AuroraSdk for PromiseCreateArgs;
    using AuroraSdk for PromiseWithCallback;
    using AuroraSdk for PromiseResult;

    event signEvent(string result);

    NEAR public near;
    IERC20 public wNEAR;
    // Sign contract account id on NEAR
    string public signer;


    constructor(string memory _signer, address _wNEAR) {
        signer = _signer;
        wNEAR = IERC20(_wNEAR);
        near = AuroraSdk.initNear(wNEAR);
    }

    function sign(string memory payload, string memory path, uint256 version) public payable {
        wNEAR.transferFrom(msg.sender, address(this), ATACH_DEPOSIT);
        bytes memory _data = hexStringToBytes(payload);
        require(_data.length == 32, "Payload must be 32 bytes");
        bytes memory data = createData(_data, path, version);
        PromiseCreateArgs memory callSign = near.call(signer, "sign", data, ATACH_DEPOSIT,  SIGN_NEAR_GAS);
        PromiseCreateArgs memory callback = near.auroraCall(address(this), abi.encodeWithSelector(this.signCallback.selector), 0, SIGN_CALLBACK_NEAR_GAS);

        callSign.then(callback).transact();
    }

    function signCallback() public {
        PromiseResult memory result = AuroraSdk.promiseResult(0);

        if (result.status != PromiseResultStatus.Successful) {
            revert("SignCallback failed");
        }

        string memory output = string(result.output);
        emit signEvent(output);
    }

    function getSigner() view public returns (string memory) {
        return signer;
    }

    function setSigner(string memory _signer) public {
        signer = _signer;
    }

    function createData(bytes memory data, string memory path, uint256 version) pure public returns (bytes memory) {
        return abi.encodePacked('{"request":{"payload":', stringifyBytes(data), ',"path":"', path, '","key_version":', Strings.toString(version), '}}');
    }

    function stringifyBytes(bytes memory data) public pure returns (string memory result) {
        require(data.length <= 32, "Data can't be more than 32 bytes");
        
        result = '[';

        for (uint i = 0; i < data.length - 1; i++) {
            result = string(abi.encodePacked(result, Strings.toString(uint8(data[i])), ','));
        }

        result = string(abi.encodePacked(result, Strings.toString(uint8(data[data.length - 1])), ']'));
    }

    function hexCharToDecimal(bytes1 hexChar) internal pure returns (uint8) {
        if (uint8(hexChar) >= 48 && uint8(hexChar) <= 57) {
            // '0' - '9'
            return uint8(hexChar) - 48;
        } else if (uint8(hexChar) >= 65 && uint8(hexChar) <= 70) {
            // 'A' - 'F'
            return uint8(hexChar) - 55;
        } else if (uint8(hexChar) >= 97 && uint8(hexChar) <= 102) {
            // 'a' - 'f'
            return uint8(hexChar) - 87;
        }
        revert("Invalid hex character");
    }

    // Function to convert a hex string to its decimal byte equivalent
    function hexStringToBytes(string memory hexString) public pure returns (bytes memory) {
        bytes memory hexBytes = bytes(hexString);
        require(hexBytes.length % 2 == 0, "Hex string must have an even length");

        bytes memory result = new bytes(hexBytes.length / 2);

        for (uint i = 0; i < hexBytes.length / 2; i++) {
            // Convert each pair of hex characters to a byte
            result[i] = bytes1(
                (hexCharToDecimal(hexBytes[2 * i]) << 4) +
                hexCharToDecimal(hexBytes[2 * i + 1])
            );
        }

        return result;
    }
}