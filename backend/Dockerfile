FROM node:20-alpine

ENV NODE_ENV=production
ENV LENSPILOT_API_HOST=0.0.0.0
ENV LENSPILOT_API_PORT=8787

WORKDIR /app

COPY package.json ./
COPY api ./api
COPY scripts ./scripts
COPY server.mjs ./

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "const port=process.env.PORT||process.env.LENSPILOT_API_PORT||8787; fetch('http://127.0.0.1:'+port+'/health').then((response)=>process.exit(response.ok?0:1)).catch(()=>process.exit(1));"

USER node

CMD ["node", "server.mjs"]
