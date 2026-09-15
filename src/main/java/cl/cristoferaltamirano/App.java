package cl.cristoferaltamirano;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.math.BigDecimal;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;

/** Autor: Cristofer Altamirano. API de laboratorio enlazada solamente a loopback. */
public final class App implements AutoCloseable {
    private final HttpServer server;
    private final ExecutorService executor = Executors.newCachedThreadPool();
    private final QuoteService quotes = new QuoteService();
    private final String version;

    public App(int port, String version) throws IOException {
        this.version = version;
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);
        server.setExecutor(executor);
        server.createContext("/", this::handle);
    }

    public void start() { server.start(); }
    public int port() { return server.getAddress().getPort(); }

    private void handle(HttpExchange exchange) throws IOException {
        try (exchange) {
            if (!"GET".equals(exchange.getRequestMethod())) {
                exchange.getResponseHeaders().set("Allow", "GET");
                respond(exchange, 405, "{\"error\":\"method_not_allowed\"}");
                return;
            }
            switch (exchange.getRequestURI().getPath()) {
                case "/health" -> respond(exchange, 200, "{\"status\":\"UP\"}");
                case "/version" -> respond(exchange, 200, "{\"version\":\"" + version + "\"}");
                case "/quote" -> quote(exchange);
                default -> respond(exchange, 404, "{\"error\":\"not_found\"}");
            }
        }
    }

    private void quote(HttpExchange exchange) throws IOException {
        try {
            Map<String, String> params = parameters(exchange.getRequestURI().getRawQuery());
            BigDecimal total = quotes.total(new BigDecimal(params.getOrDefault("price", "")),
                    Integer.parseInt(params.getOrDefault("quantity", "")),
                    new BigDecimal(params.getOrDefault("discount", "0")));
            respond(exchange, 200, "{\"total\":" + total.toPlainString() + ",\"currency\":\"CLP\"}");
        } catch (IllegalArgumentException exception) {
            respond(exchange, 400, "{\"error\":\"invalid_parameters\"}");
        }
    }

    private static Map<String, String> parameters(String query) {
        Map<String, String> params = new HashMap<>();
        if (query == null) return params;
        for (String entry : query.split("&")) {
            String[] pair = entry.split("=", 2);
            if (pair.length != 2) throw new IllegalArgumentException("Parametro incompleto");
            String key = URLDecoder.decode(pair[0], StandardCharsets.UTF_8);
            String value = URLDecoder.decode(pair[1], StandardCharsets.UTF_8);
            if (params.putIfAbsent(key, value) != null) throw new IllegalArgumentException("Parametro duplicado");
        }
        return params;
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
    }

    @Override public void close() { server.stop(0); executor.shutdownNow(); }

    public static void main(String[] args) throws Exception {
        int port = args.length == 0 ? 18080 : Integer.parseInt(args[0]);
        String version = App.class.getPackage().getImplementationVersion();
        App app = new App(port, version == null ? "development" : version);
        Runtime.getRuntime().addShutdownHook(new Thread(app::close));
        app.start();
        System.out.println("Cotizador " + app.version + " http://127.0.0.1:" + app.port());
    }
}
