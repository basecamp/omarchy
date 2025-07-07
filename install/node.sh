# #######################################################
# Node with nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

source ~/.bashrc

nvm install 22
corepack enable pnpm

# #######################################################
# Node global packages
npm i -g zx wrangler ts-node http-server
