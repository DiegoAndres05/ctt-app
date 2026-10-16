FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build -- --configuration docker

FROM nginx:alpine AS serve
COPY --from=build /app/dist/cttadmin/browser /usr/share/nginx/html
COPY --from=build /app/dist/cttadmin/*.txt /usr/share/nginx/html/
COPY --from=build /app/dist/cttadmin/*.json /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
