# Diseño del pipeline de integración y despliegue

Autor: Cristofer Altamirano

## Integración continua

El workflow `.github/workflows/ci.yml` ejecuta `scripts/Invoke-CI.ps1` en Windows con JDK 17 y Maven. Sus stages son:

1. **BUILD**: `mvn clean compile` compila las clases de producción.
2. **UNIT TESTS**: `mvn test` ejecuta los 15 casos de `QuoteServiceTest`.
3. **INTEGRATION TESTS**: `mvn failsafe:integration-test failsafe:verify` ejecuta los 12 casos HTTP reales de `ApiIT` y evalúa el resultado.
4. **PACKAGE**: `mvn -DskipTests package` produce el JAR, después de aprobar ambas suites. Aquí se evita repetir las pruebas que ya pasaron.
5. **EVIDENCE**: GitHub Actions conserva logs, reportes y JAR.

Los códigos de error interrumpen el pipeline. Las dependencias y plugins tienen versiones explícitas en `pom.xml`. Cada ejecución remota se vincula al SHA del commit y sus evidencias se archivan con ese identificador.

## Despliegue en ambiente de prueba

El workflow `.github/workflows/cd.yml` repite CI y ejecuta `scripts/Invoke-CD.ps1`. El laboratorio crea versiones 1.0.0 y 1.1.0 de la misma aplicación para demostrar trazabilidad de artefactos y recuperación; no atribuye cambios funcionales distintos a cada versión.

`Deploy.ps1` copia el artefacto a un directorio de releases, registra su versión y SHA-256, lo levanta en el puerto candidato 18081 y ejecuta aceptación antes de modificar el servicio activo en 18080. Si el candidato falla, conserva el servicio previo. Si pasa, detiene el proceso registrado, inicia el nuevo JAR en el puerto de staging y repite aceptación.

## Aceptación

Los seis casos verifican: disponibilidad UP; versión exacta del manifiesto; total 2142 CLP con descuento; total 1190 sin descuento; HTTP 400 para cantidad cero; y HTTP 404 para una ruta inexistente. Cualquier incumplimiento lanza una excepción y detiene el stage.

## Rollback

El estado del despliegue conserva `current` y `previous`. Cada release registra ruta inmutable, versión y SHA-256. El rollback manual verifica que el hash previo no haya cambiado, detiene el proceso actual, inicia el JAR anterior y ejecuta nuevamente los seis casos de aceptación. Después actualiza el estado.

El rollback automático se aplica cuando la activación o la validación posterior fallan. El script recupera el artefacto que estaba activo antes del intento, comprueba su hash y valida por HTTP la versión recuperada. El error del despliegue se propaga para impedir que un despliegue fallido se presente como éxito. Solo la demostración `Invoke-CD.ps1` reconoce el incidente deliberado y verifica que la recuperación sí haya funcionado.

## Evidencia y criterios de éxito

- CI: 15 casos unitarios y 12 de integración; cero fallos y errores; JAR generado.
- Deploy: `/version` devuelve 1.1.0 en staging y seis pruebas de aceptación aprobadas.
- Rollback manual: `/version` devuelve 1.0.0 y el hash coincide con el JAR de referencia.
- Rollback automático: el incidente se detecta; el servicio vuelve a 1.0.0; se repiten aceptación y verificación de hash.
- Los procesos creados por la demostración se detienen en `finally`, incluso ante errores.

## Alcance del laboratorio

El servicio no utiliza base de datos, de modo que el rollback solo necesita recuperar el artefacto ejecutable. En una aplicación con persistencia también habría que diseñar migraciones compatibles, respaldo y recuperación de datos. El proceso tiene una breve interrupción durante el reinicio; la pauta admite rollback como alternativa a Canary o Blue-Green. El runner de Actions y su staging se eliminan al finalizar la ejecución.
