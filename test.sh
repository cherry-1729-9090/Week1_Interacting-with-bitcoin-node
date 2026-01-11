# Setup nvm and install pre-req
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
nvm install --lts
nvm use --lts

# Install dependencies in root directory (for Jest tests)  
npm install

# Install dependencies in javascript directory (for bitcoin-core)
cd javascript && npm install && cd ..

# Clean up any previous state
rm -f out.txt

# Spawn Bitcoind, and provide execution permission.
docker compose up -d
chmod +x ./bash/run-bash.sh
chmod +x ./python/run-python.sh
chmod +x ./javascript/run-javascript.sh
chmod +x ./rust/run-rust.sh
chmod +x ./run.sh

# Wait for Bitcoin node to be ready
echo "Waiting for Bitcoin node to start..."
sleep 5

# Try to connect to Bitcoin node (cross-platform timeout)
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 30"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 30"
else
    # Fallback: just try for a reasonable amount of time without timeout
    TIMEOUT_CMD=""
fi

if [ -n "$TIMEOUT_CMD" ]; then
    $TIMEOUT_CMD bash -c 'until curl -s --fail -u alice:password -X POST --data "{\"jsonrpc\":\"1.0\",\"id\":\"test\",\"method\":\"getblockchaininfo\",\"params\":[]}" http://127.0.0.1:18443/ > /dev/null; do sleep 1; done' || {
        echo "ERROR: Bitcoin node failed to start properly"
        docker compose logs bitcoin
        docker compose down -v
        exit 1
    }
else
    # Fallback without timeout command
    for i in {1..30}; do
        if curl -s --fail -u alice:password -X POST --data '{"jsonrpc":"1.0","id":"test","method":"getblockchaininfo","params":[]}' http://127.0.0.1:18443/ > /dev/null; then
            break
        fi
        if [ $i -eq 30 ]; then
            echo "ERROR: Bitcoin node failed to start properly"
            docker compose logs bitcoin
            docker compose down -v
            exit 1
        fi
        sleep 1
    done
fi

echo "Bitcoin node is ready"

# Run the test scripts - MUST succeed
set -e
echo "Running student solution..."
if ! /bin/bash run.sh; then
    echo "ERROR: Student solution failed to execute"
    docker compose down -v
    exit 1
fi

# Verify out.txt was created
if [ ! -f "out.txt" ]; then
    echo "ERROR: out.txt file not created by solution"
    docker compose down -v
    exit 1
fi

# Verify out.txt contains a valid transaction ID
TXID=$(cat out.txt | tr -d '\n\r ')
if [ ${#TXID} -ne 64 ] || [[ ! $TXID =~ ^[a-fA-F0-9]{64}$ ]]; then
    echo "ERROR: out.txt does not contain a valid 64-character hex transaction ID"
    echo "Found: '$TXID' (length: ${#TXID})"
    docker compose down -v
    exit 1
fi

echo "Solution executed successfully, running validation tests..."

# Run the validation tests
npm run test

# Stop the docker.
docker compose down -v