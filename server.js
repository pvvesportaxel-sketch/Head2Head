
const http = require("http");
const WebSocket = require("ws");

const PORT = process.env.PORT || 10000;

const server = http.createServer((req, res) => {
    res.writeHead(200, {
        "Content-Type": "application/json"
    });

    res.end(JSON.stringify({
        name: "HEAD2HEAD ONLINE",
        status: "running",
        players: wss.clients.size
    }));
});

const wss = new WebSocket.Server({ server });

let waitingPlayer = null;

wss.on("connection", (socket) => {
    console.log("Player connected");

    socket.send(JSON.stringify({
        type: "CONNECTED"
    }));

    if (waitingPlayer && waitingPlayer.readyState === WebSocket.OPEN) {
        const room = [waitingPlayer, socket];

        room.forEach(player => {
            player.room = room;

            player.send(JSON.stringify({
                type: "MATCH_FOUND"
            }));
        });

        waitingPlayer = null;
        console.log("Match created");
    } else {
        waitingPlayer = socket;

        socket.send(JSON.stringify({
            type: "WAITING"
        }));
    }

    socket.on("message", (message) => {
        const room = socket.room || [];

        room.forEach(player => {
            if (player !== socket &&
                player.readyState === WebSocket.OPEN) {
                player.send(message);
            }
        });
    });

    socket.on("close", () => {
        if (waitingPlayer === socket) {
            waitingPlayer = null;
        }

        (socket.room || []).forEach(player => {
            if (player !== socket &&
                player.readyState === WebSocket.OPEN) {
                player.send(JSON.stringify({
                    type: "OPPONENT_DISCONNECTED"
                }));

                player.room = null;
            }
        });

        console.log("Player disconnected");
    });
});

server.listen(PORT, "0.0.0.0", () => {
    console.log("HEAD2HEAD SERVER RUNNING ON " + PORT);
});
