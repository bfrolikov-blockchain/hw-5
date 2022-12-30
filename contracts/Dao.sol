// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
import "hardhat/console.sol";

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract Dao {
    uint256 private constant MAX_PROPOSALS = 3;
    uint256 private constant TTL = 259200;

    /// @dev Indexing from 1 becase there is no way to determine if a key exists in a mapping,
    ///      and the default value is 0
    Proposal[MAX_PROPOSALS + 1] private _proposals;

    mapping(bytes32 => uint256) private _proposalIndices;

    /// @dev This is used to handle the situation when the voter votes again
    ///      with a different number of tokens
    mapping(uint256 => mapping(address => Vote)) private _lastVotes;

    /// @dev Have to reset votes when the proposal is processed.
    ///      Can't use `delete` with mapping, have to delete individual keys
    mapping(uint256 => address[]) private _proposalVoters;

    IVotes private _daoVotes;

    /// @notice Indicates that a proposal has been discarded
    /// @param proposalHash - hash that represents the proposal
    event ProposalDiscarded(bytes32 proposalHash);

    /// @notice Indicates that a proposal has been accepted
    /// @param proposalHash - hash that represents the proposal
    event ProposalAccepted(bytes32 proposalHash);

    /// @notice Indicates that a proposal has been rejected
    /// @param proposalHash - hash that represents the proposal
    event ProposalRejected(bytes32 proposalHash);

    /// @param daoVotes - dao token address
    constructor(address daoVotes) {
        _daoVotes = IVotes(daoVotes);
    }

    modifier proposalExists(bytes32 proposalHash) {
        require(_proposalIndices[proposalHash] > 0, "Proposal doesn't exist");
        _;
    }
    
    /// @notice returns the maximum number of proposals
    function getMaxProposals() public pure returns (uint256) {
        return MAX_PROPOSALS;
    }

    /// @notice Returns a snapshot of all currently stored proposals
    /// @notice Should not be relied upon to check for expiration
    function getProposals()
        public
        view
        returns (Proposal[MAX_PROPOSALS] memory)
    {
        Proposal[MAX_PROPOSALS] memory proposals;
        for (uint256 i = 1; i < MAX_PROPOSALS + 1; i++) {
            proposals[i] = _proposals[i];
        }
        return proposals;
    }

    /// @notice Get last vote for a specific proposal for a specific user
    /// @param proposalHash - hash that repesents the proposal.
    /// @param voter - voter to get the last vote for
    /// @return Vote or default value if absent
    function getLastVoteFor(
        bytes32 proposalHash,
        address voter
    ) public view proposalExists(proposalHash) returns (Vote memory) {
        return _lastVotes[_proposalIndices[proposalHash]][voter];
    }

    /// @notice Get all voters for a specific proposal
    /// @param proposalHash - hash that repesents the proposal. 
    /// @return array of voter addresses
    function getVoters(
        bytes32 proposalHash
    ) public view proposalExists(proposalHash) returns (address[] memory) {
        return _proposalVoters[_proposalIndices[proposalHash]];
    }

    /// @notice Creates a proposal
    /// @param proposalHash - hash that represents the proposal,
    ///        must not match any existing non-processed proposal
    function createProposal(bytes32 proposalHash) external {
        require(_proposalIndices[proposalHash] == 0, "Proposal already exists");
        uint256 insertIndex = _getInsertIndex();
        require(insertIndex > 0, "No space for new proposal");
        address[] storage voters = _proposalVoters[insertIndex];
        for (uint i = 0; i < voters.length; i++) {
            delete _lastVotes[insertIndex][voters[i]];
        }
        delete _proposalVoters[insertIndex];

        _proposals[insertIndex] = Proposal({
            proposalHash: proposalHash,
            state: ProposalState.INDEFINITE,
            votesFor: 0,
            votesAgainst: 0,
            creationTimestamp: block.timestamp,
            creationBlock: block.number
        });
        _proposalIndices[proposalHash] = insertIndex;
    }

    /// @notice Vote for a proposal
    /// @notice Voting amount will be the amount of currently delegated votes
    /// @notice Voting again is possible, however the voting amount must
    ///         not exceed the amount of delegated votes at the moment when
    ///         the proposal was created (this moment in time is represented by block.number)
    /// @param proposalHash - hash that repesents the proposal. The proposal must be created beforehand.
    /// @param voteFor - if true, vote for a proposal. If false - vote against a proposal
    function vote(
        bytes32 proposalHash,
        bool voteFor
    ) external proposalExists(proposalHash) {
        uint256 proposalIndex = _proposalIndices[proposalHash];
        Proposal storage voteProposal = _proposals[proposalIndex];
        require(
            voteProposal.state == ProposalState.INDEFINITE,
            "Proposal is in an invalid state for voting"
        );

        if (_checkExpiration(voteProposal)) {
            return;
        }

        uint256 voteAmount = _daoVotes.getVotes(msg.sender);
        require(voteAmount > 0, "Vote amount must be greater than 0");

        require(
            voteAmount <=
                _daoVotes.getPastVotes(msg.sender, voteProposal.creationBlock),
            "Can't vote with more tokens than during proposal creation"
        );

        Vote storage lastVote = _lastVotes[proposalIndex][msg.sender];
        if (lastVote.amount == 0) {
            _proposalVoters[proposalIndex].push(msg.sender);
        }

        if (lastVote.voteFor) {
            voteProposal.votesFor -= lastVote.amount;
        } else {
            voteProposal.votesAgainst -= lastVote.amount;
        }

        if (voteFor) {
            voteProposal.votesFor += voteAmount;
        } else {
            voteProposal.votesAgainst += voteAmount;
        }

        _checkThreshold(voteProposal);

        lastVote.amount = voteAmount;
        lastVote.voteFor = voteFor;
    }

    /// @dev Find a place for inserting a new proposal and set state accordingly
    function _getInsertIndex() private returns (uint256) {
        for (uint256 i = 1; i < MAX_PROPOSALS + 1; i++) {
            Proposal storage currentProposal = _proposals[i];
            if (
                _checkExpiration(currentProposal) ||
                currentProposal.state != ProposalState.INDEFINITE
            ) {
                return i;
            }
        }
        return 0;
    }

    /// @dev Check that a prososal is expired and set state accordingly
    function _checkExpiration(
        Proposal storage proposal
    ) private returns (bool) {
        if (proposal.state == ProposalState.DISCARDED) {
            return true;
        }

        if (
            proposal.state != ProposalState.UNINITIALIZED &&
            block.timestamp >= proposal.creationTimestamp + TTL
        ) {
            proposal.state = ProposalState.DISCARDED;
            _processStatus(proposal);
            return true;
        }

        return false;
    }

    /// @dev Check that a prososal is accepted/rejected and set state accordingly
    function _checkThreshold(Proposal storage proposal) private {
        uint256 thresholdAtCreation = _daoVotes.getPastTotalSupply(
            proposal.creationBlock
        ) / 2;
        if (proposal.votesFor >= thresholdAtCreation) {
            proposal.state = ProposalState.ACCEPTED;
            _processStatus(proposal);
        } else if (proposal.votesAgainst >= thresholdAtCreation) {
            proposal.state = ProposalState.REJECTED;
            _processStatus(proposal);
        }
    }

    /// @dev Reset index and emit event
    function _processStatus(Proposal storage proposal) private {
        delete _proposalIndices[proposal.proposalHash];
        ProposalState state = proposal.state;

        if (state == ProposalState.ACCEPTED) {
            emit ProposalAccepted(proposal.proposalHash);
        } else if (state == ProposalState.REJECTED) {
            emit ProposalRejected(proposal.proposalHash);
        } else if (state == ProposalState.DISCARDED) {
            emit ProposalDiscarded(proposal.proposalHash);
        } else {
            revert("Invalid proposal state on processing status");
        }
    }
}

enum ProposalState {
    UNINITIALIZED,
    ACCEPTED,
    REJECTED,
    DISCARDED,
    INDEFINITE
}

struct Vote {
    bool voteFor;
    uint256 amount;
}

struct Proposal {
    bytes32 proposalHash;
    ProposalState state;
    uint256 votesFor;
    uint256 votesAgainst;
    uint256 creationTimestamp;
    uint256 creationBlock;
}
