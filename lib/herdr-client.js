"use strict";
// Client for the Herdr socket API: newline-delimited JSON over a local Unix
// socket (named pipe on Windows).
//
// The server handles exactly one request per connection and then closes, with
// one exception: `events.subscribe` takes over the stream and pushes events
// until the client disconnects. So a request opens a short-lived connection,
// and each subscription owns a dedicated long-lived one.

const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const { EventEmitter } = require("node:events");

function socketPath() {
  if (process.env.HERDR_SOCKET_PATH) return process.env.HERDR_SOCKET_PATH;
  if (process.platform === "win32") return "\\\\.\\pipe\\herdr";
  const base = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config");
  return path.join(base, "herdr", "herdr.sock");
}

let seq = 0;

// One request, one connection.
function request(method, params = {}, { timeoutMs = 5000 } = {}) {
  return new Promise((resolve, reject) => {
    const p = socketPath();
    const sock = net.createConnection(p);
    sock.setEncoding("utf8");
    let buf = "";
    let settled = false;

    const finish = (err, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.destroy();
      err ? reject(err) : resolve(value);
    };

    const timer = setTimeout(
      () => finish(new Error(`timeout waiting for ${method}`)),
      timeoutMs,
    );

    sock.on("error", (err) =>
      finish(new Error(`cannot reach herdr server at ${p}: ${err.message}`)),
    );
    sock.on("connect", () => {
      sock.write(JSON.stringify({ id: `wl_${++seq}`, method, params }) + "\n");
    });
    sock.on("data", (chunk) => {
      buf += chunk;
      const nl = buf.indexOf("\n");
      if (nl < 0) return;
      let msg;
      try {
        msg = JSON.parse(buf.slice(0, nl));
      } catch (err) {
        return finish(new Error(`bad response: ${err.message}`));
      }
      if (msg.error) finish(new Error(msg.error.message || "api error"));
      else finish(null, msg.result);
    });
    sock.on("close", () =>
      finish(new Error(`connection closed before ${method} responded`)),
    );
  });
}

// A dedicated connection streaming one or more subscriptions.
// Emits "ready" after the acknowledgement, "event" per pushed event, "closed"
// when the stream ends.
class EventStream extends EventEmitter {
  constructor(subscriptions) {
    super();
    this.subscriptions = subscriptions;
    this.sock = null;
    this.buf = "";
    this.ready = false;
    this.closed = false;
  }

  start() {
    const sock = net.createConnection(socketPath());
    sock.setEncoding("utf8");
    this.sock = sock;
    sock.on("connect", () => {
      sock.write(
        JSON.stringify({
          id: `wl_sub_${++seq}`,
          method: "events.subscribe",
          params: { subscriptions: this.subscriptions },
        }) + "\n",
      );
    });
    sock.on("data", (chunk) => this._onData(chunk));
    sock.on("error", (err) => this._close(err));
    sock.on("close", () => this._close(null));
    return this;
  }

  _onData(chunk) {
    this.buf += chunk;
    let nl;
    while ((nl = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, nl).trim();
      this.buf = this.buf.slice(nl + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      if (!this.ready) {
        this.ready = true;
        if (msg.error) {
          this.emit("error", new Error(msg.error.message || "subscribe failed"));
          continue;
        }
        this.emit("ready", msg.result);
        continue;
      }
      this.emit("event", msg);
    }
  }

  _close(err) {
    if (this.closed) return;
    this.closed = true;
    if (this.sock) {
      this.sock.destroy();
      this.sock = null;
    }
    this.emit("closed", err);
  }

  stop() {
    this.closed = true;
    if (this.sock) {
      this.sock.destroy();
      this.sock = null;
    }
  }
}

// Agents in a stable order so a physical key keeps pointing at the same agent
// for as long as the set of agents is unchanged.
function sortAgents(agents) {
  return [...agents].sort((a, b) => {
    const key = (x) =>
      `${x.workspace_id || ""} ${x.tab_id || ""} ${x.pane_id || ""}`;
    return key(a).localeCompare(key(b));
  });
}

async function listAgents() {
  const result = await request("agent.list");
  return sortAgents(result.agents || []);
}

function focusAgent(target) {
  return request("agent.focus", { target });
}

module.exports = {
  request,
  EventStream,
  socketPath,
  listAgents,
  sortAgents,
  focusAgent,
};
