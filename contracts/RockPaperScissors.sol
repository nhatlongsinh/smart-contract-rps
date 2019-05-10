pragma solidity >=0.4.21 <0.6.0;

import './Stoppable.sol';
import './SafeMath.sol';

contract RockPaperScissors is Stoppable {
    // library
    using SafeMath for uint;

    // DATA
    enum Move {Unset, Rock, Paper, Scissors}

    struct Game {
        uint256 betAmount;
        uint256 deadlineBlock;
        bytes32 opponentHash; // hash of real move + secret
        Move creatorMove;
        Move opponentMove;
        address firstRevealer;
        address opponent;
        address creator;
    }

    // PRIVATE VARIABLES
    // deadline duration serves as duration after which game creator has to wait to cancel his game
    // as well as the duration within which the player 2 has to reveal his move
    uint256 public deadlineDuration;
    // game id is creatorHash
    mapping(bytes32 => Game) public games;
    mapping(address => uint256) public balances;

    // EVENTS
    event GameCreated(
        address indexed sender, // as creator
        uint256 amount,
        bytes32 indexed gameId // as creator hash
    );
    event GamePlayed(
        address indexed sender, // as opponent
        bytes32 indexed gameId,
        bytes32 hashMove // hash move
    );
    event GameRevealed(
        address indexed sender, // as opponent
        bytes32 indexed gameId,
        Move move,
        bytes32 secret
    );

    event GameCancelled(address indexed sender, bytes32 indexed gameId);

    event GameEnded(address indexed winner, bytes32 indexed gameId);

    event GameClaimed(address indexed sender, bytes32 indexed gameId);

    event BalanceWithdrawed(address indexed sender, uint256 amount);

    event DeadlineDurationChanged(address indexed sender, uint256 newValue);

    constructor(bool isRunning, uint256 _deadlineDuration)
        public
        Stoppable(isRunning)
    {
        setDeadlineDuration(_deadlineDuration);
    }

    function setDeadlineDuration(uint256 _deadlineDuration) public ownerOnly {
        require(_deadlineDuration > 0, "deadline duration must greater than zero");
        deadlineDuration = _deadlineDuration;

        emit DeadlineDurationChanged(msg.sender, _deadlineDuration);
    }

    // creator create a new game by submitting his hashMove and opponent address
    // hashMove will be game id
    function createGame(address opponent, bytes32 hashMove) public payable runningOnly {
        require(opponent != address(0), "Opponent must be valid");

        Game storage game = games[hashMove];
        require(game.creator == address(0), "Game hash already exist");

        game.opponent = opponent;
        game.betAmount = msg.value;
        game.creator = msg.sender;

        emit GameCreated(msg.sender, msg.value, hashMove);
    }

    // opponent play the game by submitting his hashMove
    function play(bytes32 gameId, bytes32 hashMove) public payable runningOnly {
        Game memory game = games[gameId];

        require(game.opponent == msg.sender, "You are not the player");
        require(game.opponentHash == bytes32(0), "Opponent already played");
        require(game.betAmount == msg.value, "Amount is invalid");

        games[gameId].opponentHash = hashMove;
        // this deadline block is for cancel period
        games[gameId].deadlineBlock = block.number.add(deadlineDuration);

        emit GamePlayed(msg.sender, gameId, hashMove);
    }

    // players reveal their real moves by submitting move and secret
    function revealGame(bytes32 gameId, Move move, bytes32 secret) public runningOnly {
        Game memory game = games[gameId];

        require(move != Move.Unset, "Only Rock, Paper, or Scissors allowed");
        require(game.opponentHash != bytes32(0), "Opponent has not played yet");
        
        // only check revealing expire block when the first player already reveal
        if(game.firstRevealer != address(0)) {
            require(game.deadlineBlock >= block.number, "Revealing period is expired");
        } else {
            // set first revealer & set revealing expired block
            games[gameId].firstRevealer = msg.sender;
            // this deadline block is for revealing period
            games[gameId].deadlineBlock = block.number.add(deadlineDuration);
        }

        bytes32 hashMove = generateHash(msg.sender, move, secret);

        // save real move to the right sender
        if(game.creator == msg.sender){
            require(gameId == hashMove, "Invalid game move");
            require(game.creatorMove == Move.Unset, "Move already revealed");
            games[gameId].creatorMove = move;
            game.creatorMove = move;
        } else if(game.opponent == msg.sender) {
            require(game.opponentHash == hashMove, "Invalid game move");
            require(game.opponentMove == Move.Unset, "Move already revealed");
            games[gameId].opponentMove = move;
            game.opponentMove = move;
        } else {
            revert("You are not the player");
        }

        emit GameRevealed(msg.sender, gameId, move, secret);

        // calculate winner when both have submitted their moves
        if(game.creatorMove != Move.Unset && game.opponentMove != Move.Unset) {
            int256 result = calculateResult(game.creatorMove, game.opponentMove);
            address winner;

            if(result == 0) {
                // even - refund balance to players
                if(game.betAmount > 0) {
                    balances[game.creator] = balances[game.creator].add(game.betAmount);
                    balances[game.opponent] = balances[game.opponent].add(game.betAmount);
                }
            } else {
                // identify winner
                if(result > 0) {
                    winner = game.creator;
                } else if(result < 0) {
                    winner = game.opponent;
                } else {
                    assert(false);
                }
                
                // winner receive reward
                if(game.betAmount > 0) {
                    balances[winner] = balances[winner].add(game.betAmount.mul(2));
                }
            }

            // clear storage
            Game storage endGame = games[gameId];
            endGame.betAmount = 0;
            endGame.deadlineBlock = 0;
            endGame.opponentHash = 0;
            endGame.creatorMove = Move.Unset;
            endGame.opponentMove = Move.Unset;
            endGame.firstRevealer = address(0);
            endGame.opponent = address(0);

            emit GameEnded(winner, gameId);
        }
    }

    // Play 1 can claim the price if player 2 does not reveal his move with the revealing period
    function claimExpiredGame(bytes32 gameId) public runningOnly {
        // clear storage
        Game storage endGame = games[gameId];

        require(endGame.firstRevealer == msg.sender, "Only first revealer can claim");
        require(endGame.creatorMove == Move.Unset || endGame.opponentMove == Move.Unset, "Both players have revealed their moves");
        require(endGame.deadlineBlock < block.number, "Game is not expired");

        if(endGame.betAmount > 0) {
            balances[msg.sender] = balances[msg.sender].add(endGame.betAmount.mul(2));
        }
        
        endGame.betAmount = 0;
        endGame.deadlineBlock = 0;
        endGame.opponentHash = 0;
        endGame.creatorMove = Move.Unset;
        endGame.opponentMove = Move.Unset;
        endGame.firstRevealer = address(0);
        endGame.opponent = address(0);

        emit GameClaimed(msg.sender, gameId);
    }

    // cancel game only if Opponent has not played yet
    function cancelGame(bytes32 gameId) public runningOnly {
        Game memory game = games[gameId];

        require(game.creator == msg.sender, "Only owner can cancel this game");
        require(game.opponentHash == bytes32(0), "Opponent already played");
        require(game.deadlineBlock < block.number, "Cancel is not available");

        games[gameId].betAmount = 0;
        games[gameId].deadlineBlock = 0;

        if(game.betAmount > 0)
            balances[msg.sender] = balances[msg.sender].add(game.betAmount);

        emit GameCancelled(msg.sender, gameId);
    }

    // withdraw balance
    function withdrawBalance() public runningOnly{
        uint256 balance = balances[msg.sender];

        require(balance > 0, "You have no balance");

        balances[msg.sender] = 0;

        emit BalanceWithdrawed(msg.sender, balance);

        msg.sender.transfer(balance);
    }
    
    // 0: even, 1: player1 win, -1: player2 win
    function calculateResult(Move move1, Move move2) public pure returns(int256 result) {
        if(move1 == move2) {
            result = 0;
        } else if(move1 == Move.Rock) {
            if(move2 == Move.Paper) {
                result = -1;
            } else if(move2 == Move.Scissors) {
                result = 1;
            }
        } else if(move1 == Move.Paper) {
            if(move2 == Move.Scissors) {
                result = -1;
            } else if(move2 == Move.Rock) {
                result = 1;
            }
        } else if(move1 == Move.Scissors) {
            if(move2 == Move.Rock) {
                result = -1;
            } else if(move2 == Move.Paper) {
                result = 1;
            }
        } else {
            assert(false);
        }
    }

    function generateHash(address player, Move move, bytes32 secret)
        public
        view
        returns(bytes32 result)
    {
        require(move != Move.Unset, "Invalid Move");
        result = keccak256(
            abi.encodePacked(this, player, move, secret)
        );
    }
}