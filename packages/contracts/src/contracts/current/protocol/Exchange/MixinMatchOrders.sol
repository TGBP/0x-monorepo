/*
  Copyright 2018 ZeroEx Intl.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/

pragma solidity ^0.4.21;
pragma experimental ABIEncoderV2;

import "./mixins/MExchangeCore.sol";
import "./mixins/MMatchOrders.sol";
import "./mixins/MSettlement.sol";
import "../../utils/SafeMath/SafeMath.sol";
import "./LibOrder.sol";
import "./LibStatus.sol";
import "./LibPartialAmount";

contract MixinMatchOrders is LibOrder, LibStatus, SafeMath, MMatchOrders, MExchangeCore, MSettlement, LibPartialAmount {

    function validateMatchOrdersContextOrRevert(Order memory left, Order memory right)
        private
    {
        require(left.makerTokenAddress == right.takerTokenAmount);
        require(left.takerTokenAddress == right.makerTokenAmount);

        // Make sure there is a positive spread
        // TODO: Explain
        // TODO: SafeMath
        require(
            left.makerTokenAmount * right.makerTokenAmount >=
            left.takerTokenAmount * right.takerTokenAmount);
    }


    function getMatchedFillAmounts(Order memory left, Order memory right, uint256 leftFilledAmount, uint256 rightFilledAmount, uint256 takerTokenFillAmount)
        private
        returns (uint8 status, MatchedOrderFillAmounts memory matchedFillOrderAmounts)
    {
        // The goal is for taker to obtain the maximum number of left maker
        // token.

        // The constraint can be either on the left or on the right. We need to
        // determine where it is.

        uint256 leftRemaining = safeSub(left.takerTokenAmount, leftFilledAmount);
        uint256 rightRemaining = safeSub(right.takerTokenAmount, rightFilledAmount);

        // TODO: SafeMath
        if(right.makerTokenAmount * rightRemaining <
            right.takerTokenAmount * leftRemaining)
        {
            // leftRemaining is the constraint: maximally fill left
            (   status,
                matchedFillOrderAmounts.leftMakerTokenFilledAmount,
                matchedFillOrderAmounts.leftTakerTokenFilledAmount,
                matchedFillOrderAmounts.leftMakerFeeAmountPaid,
                matchedFillOrderAmounts.leftTakerFeeAmountPaid
            ) = getFillAmounts(
                left,
                leftRemaining,
                takerTokenFillAmount,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return status;
            }

            // Compute how much we should fill right to satisfy
            // leftTakerTokenFilledAmount
            // TODO: Check if rounding is in the correct direction.
            uint256 rightFill = getPartialAmount(
                right.makerTokenAmount,
                right.takerTokenAmount,
                matchedFillOrderAmounts.leftMakerTokenFilledAmount);

            // Compute right fill amounts
            (   status,
                matchedFillOrderAmounts.rightMakerTokenFilledAmount,
                matchedFillOrderAmounts.rightTakerTokenFilledAmount,
                matchedFillOrderAmounts.rightMakerFeeAmountPaid,
                matchedFillOrderAmounts.rightTakerFeeAmountPaid
            ) = getFillAmounts(
                right,
                rightFill,
                takerTokenFillAmount,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return status;
            }

            // Unfortunately, this is no longer exact and taker may end up
            // with some left.takerTokens. This will be a rounding error amount.
            // We should probably not bother and just give them to the makers.
            assert(matchedFillOrderAmounts.rightMakerTokenFilledAmount >= matchedFillOrderAmounts.leftTakerTokenFilledAmount);

            // TODO: Make sure the difference is neglible

        } else {
            // rightRemaining is the constraint: maximally fill right
            (   status,
                matchedFillOrderAmounts.rightMakerTokenFilledAmount,
                matchedFillOrderAmounts.rightTakerTokenFilledAmount,
                matchedFillOrderAmounts.rightMakerFeeAmountPaid,
                matchedFillOrderAmounts.rightTakerFeeAmountPaid
            ) = getFillAmounts(
                right,
                rightRemaining,
                takerTokenFillAmount,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return status;
            }

            // We now have rightMakerTokens to fill left with
            assert(matchedFillOrderAmounts.rightMakerTokenFilledAmount <= remaingLeft);

            // Fill left with all the right.makerToken we received
            (   status,
                matchedFillOrderAmounts.leftMakerTokenFilledAmount,
                matchedFillOrderAmounts.leftTakerTokenFilledAmount,
                matchedFillOrderAmounts.leftMakerFeeAmountPaid,
                matchedFillOrderAmounts.leftTakerFeeAmountPaid
            ) = getFillAmounts(
                left,
                matchedFillOrderAmounts.rightMakerTokenFilledAmount,
                takerTokenFillAmount,
                msg.sender);
            if(status != uint8(Status.SUCCESS)) {
                return status;
            }

            // Taker should not have leftTakerTokens left
            assert(matchedFillOrderAmounts.rightMakerTokenFilledAmount == leftTakerTokenFilledAmount);
        }
    }

    // Match two complementary orders that overlap.
    // The taker will end up with the maximum amount of left.makerToken
    // Any right.makerToken that taker would gain because of rounding are
    // transfered to right.
    function matchOrders(
        Order memory left,
        Order memory right,
        bytes leftSignature,
        bytes rightSignature)
        public
        returns (
            uint256 leftFilledAmount,
            uint256 rightFilledAmount)
    {
        // Get left status
        uint8 status;
        bytes32 leftOrderHash;
        (   leftOrderHash,
            status,
            leftFilledAmount
        ) = getOrderStatus(left, leftSignature);
        if(status != uint8(Status.ORDER_FILLABLE)) {
            emit ExchangeStatus(uint8(status), leftOrderHash);
            return 0;
        }

        // Get right status
        bytes32 rightOrderHash;
        (   leftOrderHash,
            status,
            rightFilledAmount
        ) = getOrderStatus(left, leftSignature);
        if(status != uint8(Status.ORDER_FILLABLE)) {
            emit ExchangeStatus(uint8(status), leftOrderHash);
            return 0;
        }

        // Fetch taker address
        address takerAddress = getCurrentContextAddress();

        // Either our context is valid or we revert
        validateMatchOrdersContextOrRevert(left, right);

        // Compute proportional fill amounts
        MatchedOrderFillAmounts memory matchedFillOrderAmounts;
        (status, matchedFillOrderAmounts) = getMatchedFillAmounts(left, right, leftFilledAmount, rightFilledAmount);

        // Settle matched orders
        settleMatchedOrders(left, right, matchedFillOrderAmounts, takerAddress);

        // Update exchange internal state
        updateFilledState(
            left,
            leftOrderHash,
            matchedFillOrderAmounts.leftMakerTokenFilledAmount,
            matchedFillOrderAmounts.leftTakerTokenFilledAmount,
            matchedFillOrderAmounts.leftMakerFeeAmountPaid,
            matchedFillOrderAmounts.leftTakerFeeAmountPaid
        );
        updateFilledState(
            right,
            rightOrderHash,
            matchedFillOrderAmounts.rightMakerTokenFilledAmount,
            matchedFillOrderAmounts.rightTakerTokenFilledAmount,
            matchedFillOrderAmounts.rightMakerFeeAmountPaid,
            matchedFillOrderAmounts.rightTakerFeeAmountPaid
        );
    }
}
