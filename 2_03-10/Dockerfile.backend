FROM golang:1.16
WORKDIR /usr/src/app
COPY . .
RUN go build -o server .
EXPOSE 8080
CMD ["./server"]
