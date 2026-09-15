package cl.cristoferaltamirano;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import static org.junit.jupiter.api.Assertions.*;

/** Autor: Cristofer Altamirano. Integra HTTP real, validacion y calculo sin mocks. */
class ApiIT {
    private static App app;
    private static final HttpClient CLIENT = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    @BeforeAll static void start() throws Exception { app = new App(0, "test"); app.start(); }
    @AfterAll static void stop() { if (app != null) app.close(); }

    private HttpResponse<String> request(String path, String method) throws Exception {
        return CLIENT.send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + app.port() + path))
                .timeout(Duration.ofSeconds(5)).method(method, HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofString());
    }
    @Test void exposesHealthAndJson() throws Exception {
        var response = request("/health", "GET");
        assertEquals(200, response.statusCode());
        assertEquals("{\"status\":\"UP\"}", response.body());
        assertTrue(response.headers().firstValue("Content-Type").orElse("").contains("application/json"));
    }
    @Test void exposesVersion() throws Exception {
        var response = request("/version", "GET");
        assertEquals(200, response.statusCode()); assertEquals("{\"version\":\"test\"}", response.body());
    }
    @Test void quotesDiscountedOrder() throws Exception {
        var response = request("/quote?price=1000&quantity=2&discount=0.1", "GET");
        assertEquals(200, response.statusCode());
        assertEquals("{\"total\":2142.00,\"currency\":\"CLP\"}", response.body());
    }
    @Test void defaultsDiscountToZero() throws Exception {
        var response = request("/quote?price=1000&quantity=1", "GET");
        assertEquals(200, response.statusCode());
        assertEquals("{\"total\":1190.00,\"currency\":\"CLP\"}", response.body());
    }
    @ParameterizedTest @ValueSource(strings = {"/quote", "/quote?price=abc&quantity=1",
        "/quote?price=100&quantity=0", "/quote?price=100&quantity=1&discount=2",
        "/quote?price=1&price=2&quantity=1", "/quote?price=1&quantity"})
    void rejectsInvalidHttpInput(String path) throws Exception {
        var response = request(path, "GET");
        assertEquals(400, response.statusCode()); assertEquals("{\"error\":\"invalid_parameters\"}", response.body());
    }
    @Test void rejectsUnknownRoute() throws Exception { assertEquals(404, request("/missing", "GET").statusCode()); }
    @Test void rejectsPost() throws Exception {
        var response = request("/health", "POST");
        assertEquals(405, response.statusCode()); assertEquals("GET", response.headers().firstValue("Allow").orElse(""));
    }
}
