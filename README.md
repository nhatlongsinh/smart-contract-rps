# smart-contract-rps

## Explain

Each player submit their hash version of their move (rock, paper, or scissors). Hash is calculated by hash of contract address, player address, player move, and secret. Then each player submit their move and secret key.

The contract will verify their inputs against their hash.If even, fund will be credited to both player balance; otherwise fund will be credited to winner balance. Player then can withdraw his balance.

## functions

createGame: Player 1 (creator) submit his hashMove and bet amount with player 2 address.
play: Player 2 (opponent) submit his hashMove and bet amount with Player 1 hashMove.
revealGame: each player will reveal their move by submitting their move + secret. When the first player reveal his move, the revealExpiredBlock will be set. This function will identify winner and credit fund.
claimExpiredGame: After the reveal expire period, the first player who reveal his move can claim the reward if the other player does not reveal.
cancelGame: while player 2 hasn't play yet, player 1 can cancel his game and refund money.
withdrawBalance: each player can withdraw his balance.
