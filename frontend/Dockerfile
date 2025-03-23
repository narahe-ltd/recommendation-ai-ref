# frontend/Dockerfile
FROM node:18

WORKDIR /app
COPY package.json .
RUN npm install
COPY src ./src
COPY public ./public

CMD ["npm", "start"]