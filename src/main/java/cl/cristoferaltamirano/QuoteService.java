package cl.cristoferaltamirano;

import java.math.BigDecimal;
import java.math.RoundingMode;

/** Autor: Cristofer Altamirano. Calcula valores monetarios sin errores de coma flotante. */
public final class QuoteService {
    private static final BigDecimal VAT_FACTOR = new BigDecimal("1.19");

    public BigDecimal total(BigDecimal price, int quantity, BigDecimal discount) {
        if (price == null || discount == null || price.signum() <= 0
                || quantity < 1 || quantity > 1000
                || discount.signum() < 0 || discount.compareTo(BigDecimal.ONE) > 0) {
            throw new IllegalArgumentException("Precio positivo, cantidad 1 a 1000 y descuento 0 a 1 requeridos");
        }
        return price.multiply(BigDecimal.valueOf(quantity))
                .multiply(BigDecimal.ONE.subtract(discount))
                .multiply(VAT_FACTOR).setScale(2, RoundingMode.HALF_UP);
    }
}
