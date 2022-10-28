// SPDX-License-Identifier: MIT
// Original Copyright OpenZeppelin Contracts (last updated v4.7.0) (governance/Governor.sol)
// Copyright Fathom 2022

pragma solidity ^0.8.0;

import "./utils/cryptography/ECDSA.sol";
import "./utils/cryptography/draft-EIP712.sol";
import "./utils/introspection/ERC165.sol";
import "./utils/math/SafeCast.sol";
import "./utils/structs/DoubleEndedQueue.sol";
import "./utils/Address.sol";
import "./utils/Context.sol";
import "./utils/GovernorStructs.sol";
import "./IGovernor.sol";
import "./utils/Strings.sol";
import "../../common/libraries/BytesHelper.sol";

/**
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * This contract is abstract and requires several function to be implemented in various modules:
 *
 * - A counting module must implement {quorum}, {_quorumReached}, {_voteSucceeded} and {_countVote}
 * - A voting module must implement {_getVotes}
 * - Additionanly, the {votingPeriod} must also be implemented
 *
 * _Available since v4.3._
 */
abstract contract Governor is Context, ERC165, EIP712, IGovernor {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using SafeCast for uint256;
    using Strings for *;
    using BytesHelper for *;
    using Timers for Timers.BlockNumber;

    // struct ProposalCore {
    //     Timers.BlockNumber voteStart;
    //     Timers.BlockNumber voteEnd;
    //     bool executed;
    //     bool canceled;
    //     string description;
    // }

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    bytes32 public constant EXTENDED_BALLOT_TYPEHASH =
        keccak256("ExtendedBallot(uint256 proposalId,uint8 support,string reason,bytes params)");

    string private _name;
    uint256[] private proposalIds;

    mapping(uint256 => ProposalCore) internal _proposals;
    mapping(uint256 => string) internal _descriptions;

    // This queue keeps track of the governor operating on itself. Calls to functions protected by the
    // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {_beforeExecute},
    // consumed by the {onlyGovernance} modifier and eventually reset in {_afterExecute}. This ensures that the
    // execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
    DoubleEndedQueue.Bytes32Deque private _governanceCall;

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     *
     * The governance executing address may be different from the Governor's own address, for example it could be a
     * timelock. This can be customized by modules by overriding {_executor}. The executor is only able to invoke these
     * functions during the execution of the governor's {execute} function, and not under any other circumstances. Thus,
     * for example, additional timelock proposers are not able to change governance parameters without going through the
     * governance protocol (since v4.6).
     */
    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: onlyGovernance");
        if (_executor() != address(this)) {
            bytes32 msgDataHash = keccak256(_msgData());
            // loop until popping the expected operation - throw if deque is empty (operation not authorized)
            while (_governanceCall.popFront() != msgDataHash) {}
        }
        _;
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(
        string memory name_,
        address[] memory _signers,
        uint _numConfirmationsRequired
    ) EIP712(name_, version()) {
        _name = name_;
        signers = _signers;
        numConfirmationsRequired = _numConfirmationsRequired;

        for (uint i = 0; i < _signers.length; i++) {
            address signer = _signers[i];

            require(signer != address(0), "invalid owner");
            require(!isSigner[signer], "owner not unique");

            isSigner[signer] = true;
            signers.push(signer);
        }
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor
     *        is a third party contract)
     */
    receive() external payable virtual {
        require(_executor() == address(this), "Governor, receive():  _executor() != address(this)");
    }

    /**
     * @dev See {IGovernor-execute}.
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable virtual override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        ProposalState status = state(proposalId);
        require(
            status == ProposalState.Succeeded || status == ProposalState.Queued,
            "Governor: proposal not successful"
        );

        _proposals[proposalId].executed = true;

        emit ProposalExecuted(proposalId);

        _beforeExecute(proposalId, targets, values, calldatas, descriptionHash);
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        _afterExecute(proposalId, targets, values, calldatas, descriptionHash);

        return proposalId;
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParams}.
     */
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReasonAndParamsBySig}.
     */
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            v,
            r,
            s
        );

        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public virtual override returns (uint256) {
        require(
            getVotes(_msgSender(), block.number - 1) >= proposalThreshold(),
            "Governor: proposer votes below proposal threshold"
        );

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));

        require(targets.length == values.length, "Governor: invalid proposal length");
        require(targets.length == calldatas.length, "Governor: invalid proposal length");
        require(targets.length > 0, "Governor: empty proposal");

        ProposalCore storage proposal = _proposals[proposalId];
        require(proposal.voteStart.isUnset(), "Governor: proposal already exists");

        uint64 snapshot = block.number.toUint64() + votingDelay().toUint64();
        uint64 deadline = snapshot + votingPeriod().toUint64();

        proposal.voteStart.setDeadline(snapshot);
        proposal.voteEnd.setDeadline(deadline);
        _descriptions[proposalId] = description;

        proposalIds.push(proposalId);

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            targets,
            values,
            new string[](targets.length),
            calldatas,
            snapshot,
            deadline,
            description
        );

        return proposalId;
    }

    // TODO: Remove
    /**
     * @dev returns a proposals descriptions given an index, it will return the 
     *      last |numProposals| proposals  proposalIds, details and statusses
     */
    function getProposals(uint _numIndexes) public view override 
        returns (string[] memory, string[] memory, string[] memory) {

        uint len = proposalIds.length;

        if (len == 0) {
            string[] memory a;
            string[] memory b;
            string[] memory c;
            return (a, b, c);
        }else if(_numIndexes > len){
            _numIndexes = len;
        }

        return _getProposals1(_numIndexes);
    }

    // TODO: Remove
    function _getProposals1(uint _numIndexes) internal view returns (string[] memory, string[] memory, string[] memory) {

        string[] memory _statusses = new string[](_numIndexes);
        string[] memory _descriptionsArray = new string[](_numIndexes);
        string[] memory _proposalIds = new string[](_numIndexes);

        uint counter = proposalIds.length;

        uint indexCounter = _numIndexes - 1;

        if (_numIndexes >= counter) {
            indexCounter = counter - 1;
        }

        while (indexCounter >= 0) {

            uint _currentPropId = proposalIds[counter - 1];
            _proposalIds[indexCounter] = string(_currentPropId.toString());
            _descriptionsArray[indexCounter] = _descriptions[_currentPropId];
            _statusses[indexCounter ] = (uint8(state(_currentPropId))).toString();

            if (counter - 1 == 0){break;}
            if (indexCounter == 0){break;}

            counter--;
            indexCounter--;
        }

        return (_proposalIds, _descriptionsArray, _statusses);
    }

    // TODO: Remove
    /**
     * @dev returns all proposal Ids
     */
    function getProposalIds()public view override returns(uint[] memory){
        return proposalIds;
    }

    // TODO: Remove
    /**
     * @dev returns a proposals description given a proposal Id
     */
    function getDescription(uint _proposalId)public view override returns(string memory){
        return _descriptions[_proposalId];
    }

    /**
     * @dev See {IGovernor-getVotes}.
     */
    function getVotes(address account, uint256 blockNumber) public view virtual override returns (uint256) {
        return _getVotes(account, blockNumber, _defaultParams());
    }

    /**
     * @dev See {IGovernor-getVotesWithParams}.
     */
    function getVotesWithParams(
        address account,
        uint256 blockNumber,
        bytes memory params
    ) public view virtual override returns (uint256) {
        return _getVotes(account, blockNumber, params);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        // In addition to the current interfaceId, also support previous version of the interfaceId that did not
        // include the castVoteWithReasonAndParams() function as standard
        return
            interfaceId ==
            (type(IGovernor).interfaceId ^
                this.castVoteWithReasonAndParams.selector ^
                this.castVoteWithReasonAndParamsBySig.selector ^
                this.getVotesWithParams.selector) ||
            interfaceId == type(IGovernor).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IGovernor-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IGovernor-version}.
     */
    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state(uint256 proposalId) public view virtual override returns (ProposalState) {
        ProposalCore storage proposal = _proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        uint256 snapshot = proposalSnapshot(proposalId);

        if (snapshot == 0) {
            revert("Governor: unknown proposal id");
        }

        if (snapshot >= block.number) {
            return ProposalState.Pending;
        }

        uint256 deadline = proposalDeadline(proposalId);

        if (deadline >= block.number) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        } else {
            return ProposalState.Defeated;
        }
    }

    /**
     * @dev See {IGovernor-proposalSnapshot}.
     */
    function proposalSnapshot(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteStart.getDeadline();
    }

    /**
     * @dev See {IGovernor-proposalDeadline}.
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return _proposals[proposalId].voteEnd.getDeadline();
    }

    /**
     * @dev Part of the Governor Bravo's interface: 
            _"The number of votes required in order for a voter to become a proposer"_.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev See {IGovernor-hashProposal}.
     *
     * The proposal id is produced by hashing the RLC encoded `targets` array, the `values` array, the `calldatas` array
     * and the descriptionHash (bytes32 which itself is the keccak256 hash of the description string). This proposal id
     * can be produced from the proposal data which is part of the {ProposalCreated} event. It can even be computed in
     * advance, before the proposal is submitted.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * across multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    /**
     * @dev Register a vote for `proposalId` by `account` with a given `support`, voting `weight` and voting `params`.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal virtual;

    /**
     * @dev Internal execution mechanism. Can be overridden to implement different execution mechanism
     */
    function _execute(
        uint256, /* proposalId */
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        string memory errorMessage = "Governor: call reverted without message";
        for (uint256 i = 0; i < targets.length; ++i) {
            (bool success, bytes memory returndata) = targets[i].call{ value: values[i] }(calldatas[i]);
            Address.verifyCallResult(success, returndata, errorMessage);
        }
    }

    /**
     * @dev Hook before execution is triggered.
     */
    function _beforeExecute(
        uint256, /* proposalId */
        address[] memory targets,
        uint256[] memory, /* values */
        bytes[] memory calldatas,
        bytes32 /*descriptionHash*/
    ) internal virtual {
        if (_executor() != address(this)) {
            for (uint256 i = 0; i < targets.length; ++i) {
                if (targets[i] == address(this)) {
                    _governanceCall.pushBack(keccak256(calldatas[i]));
                }
            }
        }
    }

    /**
     * @dev Hook after execution is triggered.
     */
    function _afterExecute(
        uint256, /* proposalId */
        address[] memory, /* targets */
        uint256[] memory, /* values */
        bytes[] memory, /* calldatas */
        bytes32 /*descriptionHash*/
    ) internal virtual {
        if (_executor() != address(this)) {
            if (!_governanceCall.empty()) {
                _governanceCall.clear();
            }
        }
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal virtual returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState status = state(proposalId);

        require(
            status != ProposalState.Canceled && status != ProposalState.Expired && status != ProposalState.Executed,
            "Governor: proposal not active"
        );
        _proposals[proposalId].canceled = true;

        emit ProposalCanceled(proposalId);

        return proposalId;
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    ) internal virtual returns (uint256) {
        return _castVote(proposalId, account, support, reason, _defaultParams());
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual returns (uint256) {
        ProposalCore storage proposal = _proposals[proposalId];
        require(state(proposalId) == ProposalState.Active, "Governor: vote not currently active");

        uint256 weight = _getVotes(account, proposal.voteStart.getDeadline(), params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }

        return weight;
    }

    // TODO:  Remove 

    function _getProposalsAll(uint len) internal view returns (string[] memory, string[] memory, string[] memory) {

        string[] memory _statusses = new string[](len);
        string[] memory _descriptionsArray = new string[](len);
        string[] memory _proposalIds = new string[](len);

        uint i = len - 1;
        while(i >= 0) {
            uint _proposalId = proposalIds[i];
            _proposalIds[i] = _proposalId.toString();
            _descriptionsArray[i] = _descriptions[_proposalId];
            _statusses[i] = (uint8(state(_proposalId))).toString();

            if (i == 0) {break;}
            i--;
        }

        return (_proposalIds, _descriptionsArray, _statusses);
    }

    // TODO:  Remove 

    function _getProposals(uint _numIndexes, uint len) internal view 
        returns (string[] memory, string[] memory, string[] memory) {

        

        string[] memory _statusses = new string[](_numIndexes);
        string[] memory _descriptionsArray = new string[](_numIndexes);
        string[] memory _proposalIds = new string[](_numIndexes);

        // uint _lb = len - _numIndexes;
        uint i = _numIndexes;

        while(i > 0) {

            uint _proposalId = proposalIds[len - 1 - i];
            _proposalIds[i-1] = _proposalId.toString();
            _descriptionsArray[i-1] = _descriptions[_proposalId];
            _statusses[i-1] = (uint8(state(_proposalId))).toString();

            if (i == 0) {break;}
            i--;
        }

        return (_proposalIds, _descriptionsArray, _statusses);
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }

    /**
     * @dev Amount of votes already cast passes the threshold limit.
     */
    function _quorumReached(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Is the proposal successful or not.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual returns (bool);

    /**
     * @dev Get the voting weight of `account` at a specific `blockNumber`, for a vote as described by `params`.
     */
    function _getVotes(
        address account,
        uint256 blockNumber,
        bytes memory params
    ) internal view virtual returns (uint256);

    /**
     * @dev Default additional encoded parameters used by castVote methods that don't include them
     *
     * Note: Should be overridden by specific implementations to use an appropriate value, the
     * meaning of the additional params, in the context of that implementation
     */
    function _defaultParams() internal view virtual returns (bytes memory) {
        return "";
    }

    /* solhint-disable */

    // This can be a module of its own:
    // =========================== Turn into a module ================================

    address[] public signers;
    mapping(address => bool) public isSigner;
    uint public numConfirmationsRequired;

    // mapping from proposal id => signer => bool
    mapping(uint => mapping(address => bool)) public isConfirmed;

    // mapping from proposal id to the current number of confirmations
    mapping(uint => uint8) public numConfirmations;

    // Transaction[] public transactions;

    event ConfirmProposal(address indexed signer, uint indexed proposalId);
    event RevokeConfirmation(address indexed signer, uint indexed proposalId);
    event ExecuteProposal(address indexed signer, uint indexed proposalId);

    modifier onlySigner() {
        require(isSigner[msg.sender], "not signer");
        _;
    }

    modifier notExecuted(uint _proposalId) {
        require(!_proposals[_proposalId].executed, "proposal already executed");
        _;
    }

    modifier notConfirmed(uint _proposalId) {
        require(!isConfirmed[_proposalId][msg.sender], "proposal already confirmed");
        _;
    }

    function confirmProposal(uint _proposalId)
        public
        onlySigner
        // txExists(_proposalId)    // HERE need proposal exists
        notExecuted(_proposalId)
        notConfirmed(_proposalId)
    {
        numConfirmations[_proposalId] += 1;
        isConfirmed[_proposalId][msg.sender] = true;

        emit ConfirmProposal(msg.sender, _proposalId);
    }

    function revokeConfirmation(uint _proposalId) public onlySigner notExecuted(_proposalId) {
        require(isConfirmed[_proposalId][msg.sender], "proposal not confirmed");

        numConfirmations[_proposalId] -= 1;
        isConfirmed[_proposalId][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _proposalId);
    }

    function getsigners() public view returns (address[] memory) {
        return signers;
    }
    // ============================= End of module ================================

    /* solhint-enable */
}