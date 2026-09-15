package cl.cristoferaltamirano;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import static org.junit.jupiter.api.Assertions.*;

/** Autor: Cristofer Altamirano. Reglas de negocio, limites y redondeo monetario. */
class QuoteServiceTest {
    private final QuoteService service = new QuoteService();

    @ParameterizedTest
    @CsvSource({"1000,2,0,2380.00", "1000,2,0.10,2142.00", "1000,1,1,0.00",
                "0.01,1,0,0.01", "10.005,1,0,11.91", "1,1000,0,1190.00"})
    void calculatesTotal(String price, int quantity, String discount, String expected) {
        assertEquals(new BigDecimal(expected), service.total(new BigDecimal(price), quantity, new BigDecimal(discount)));
    }

    @ParameterizedTest
    @CsvSource({"0,1,0", "-1,1,0", "100,0,0", "100,-1,0", "100,1001,0", "100,1,-0.01", "100,1,1.01"})
    void rejectsInvalidValues(String price, int quantity, String discount) {
        assertThrows(IllegalArgumentException.class,
                () -> service.total(new BigDecimal(price), quantity, new BigDecimal(discount)));
    }

    @Test void rejectsNullPrice() {
        assertThrows(IllegalArgumentException.class, () -> service.total(null, 1, BigDecimal.ZERO));
    }
    @Test void rejectsNullDiscount() {
        assertThrows(IllegalArgumentException.class, () -> service.total(BigDecimal.ONE, 1, null));
    }
}
