
const http = require("http");
const WebSocket = require("ws");
const { randomUUID } = require("crypto");

const PORT = process.env.PORT || 10000;

const server = http.createServer((req, res) => {
    if (req.url === "/" || req.url === "/health") {
        res.writeHead(200, {
            "Content-Type": "application/json"
        });

        return res.end(JSON.stringify({
            name: "HEAD2HEAD ONLINE",
            status: "running",
            players: wss.clients.size,
            waiting: waitingPlayers.length,
            rooms: activeRooms.size
        }));
    }

    res.writeHead(404);
    res.end("Not Found");
});

const wss = new WebSocket.Server({
    server,
    maxPayload: 64 * 1024
});

let waitingPlayers = [];
let activeRooms = new Set();

function send(socket, data) {
    if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify(data));
    }
}

function removeFromQueue(socket) {
    waitingPlayers = waitingPlayers.filter(
        player => player !== socket
    );

    socket.inQueue = false;
}

function addToQueue(socket) {
    if (
        socket.readyState !== WebSocket.OPEN ||
        socket.room ||
        socket.inQueue
    ) {
        return;
    }

    socket.inQueue = true;
    waitingPlayers.push(socket);

    send(socket, {
        type: "WAITING"
    });

    console.log("Player added to matchmaking queue");

    matchPlayers();
}

function matchPlayers() {
    while (waitingPlayers.length >= 2) {
        const player1 = waitingPlayers.shift();
        const player2 = waitingPlayers.shift();

        player1.inQueue = false;
        player2.inQueue = false;

        if (
            player1.readyState !== WebSocket.OPEN ||
            player2.readyState !== WebSocket.OPEN
        ) {
            if (player1.readyState === WebSocket.OPEN) {
                addToQueue(player1);
            }

            if (player2.readyState === WebSocket.OPEN) {
                addToQueue(player2);
            }

            continue;
        }

        const room = {
            id: randomUUID(),
            players: [player1, player2]
        };

        player1.room = room;
        player2.room = room;

        activeRooms.add(room);

        room.players.forEach(player => {
            send(player, {
                type: "MATCH_FOUND",
                roomId: room.id
            });
        });

        console.log("MATCH CREATED:", room.id);
    }
}

wss.on("connection", socket => {
    console.log("Player connected");

    socket.isAlive = true;
    socket.inQueue = false;
    socket.room = null;

    send(socket, {
        type: "CONNECTED"
    });

    addToQueue(socket);

    socket.on("message", message => {
        const room = socket.room;

        if (!room) return;

        room.players.forEach(player => {
            if (
                player !== socket &&
                player.readyState === WebSocket.OPEN
            ) {
                player.send(message);
            }
        });
    });

    socket.on("pong", () => {
        socket.isAlive = true;
    });

    socket.on("error", error => {
        console.log("Socket error:", error.message);
    });

    socket.on("close", () => {
        console.log("Player disconnected");

        removeFromQueue(socket);

        const room = socket.room;

        if (room) {
            activeRooms.delete(room);

            room.players.forEach(player => {
                if (player !== socket) {
                    player.room = null;

                    if (player.readyState === WebSocket.OPEN) {
                        send(player, {
                            type: "OPPONENT_DISCONNECTED"
                        });

                        addToQueue(player);
                    }
                }
            });

            socket.room = null;
        }

        console.log("Remaining players:", wss.clients.size);
    });
});

// Connection heartbeat
const heartbeat = setInterval(() => {
    wss.clients.forEach(socket => {
        if (!socket.isAlive) {
            console.log("Terminating inactive connection");
            return socket.terminate();
        }

        socket.isAlive = false;
        socket.ping();
    });
}, 30000);

wss.on("close", () => {
    clearInterval(heartbeat);
});

wss.on("error", error => {
    console.log("WebSocket server error:", error.message);
});

server.listen(PORT, "0.0.0.0", () => {
    console.log(
        "HEAD2HEAD SERVER RUNNING ON PORT " + PORT
    );
});
