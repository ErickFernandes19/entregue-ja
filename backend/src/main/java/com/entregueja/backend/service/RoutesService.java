
package com.entregueja.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Service
public class RoutesService {

    private static final String ROUTES_URL =
            "https://routes.googleapis.com/directions/v2:computeRoutes";

    private static final String FIELD_MASK = String.join(",",
            "routes.duration",
            "routes.staticDuration",
            "routes.distanceMeters",
            "routes.polyline.encodedPolyline",
            "routes.optimizedIntermediateWaypointIndex",
            "routes.legs.distanceMeters",
            "routes.legs.duration",
            "routes.legs.staticDuration",
            "routes.legs.startLocation",
            "routes.legs.endLocation",
            "routes.legs.steps.distanceMeters",
            "routes.legs.steps.staticDuration",
            "routes.legs.steps.startLocation",
            "routes.legs.steps.endLocation",
            "routes.legs.steps.navigationInstruction.instructions",
            "routes.legs.steps.navigationInstruction.maneuver",
            "routes.legs.steps.polyline.encodedPolyline"
    );

    @Value("${google.routes.api-key}")
    private String apiKey;

    private final RestTemplate restTemplate = new RestTemplate();

    public ResponseEntity<String> calcularRota(Map<String, Object> body) {

        if (apiKey == null || apiKey.isBlank()) {
            System.err.println("Chave da Routes API não configurada.");

            return ResponseEntity
                    .status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("""
                            {"error":"Chave da Routes API não configurada no backend"}
                            """);
        }

        if (body == null ||
                !body.containsKey("origin") ||
                !body.containsKey("destination")) {

            System.err.println("Solicitação de rota sem origem ou destino.");

            return ResponseEntity
                    .badRequest()
                    .body("""
                            {"error":"Origem e destino são obrigatórios"}
                            """);
        }

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Goog-Api-Key", apiKey);
        headers.set("X-Goog-FieldMask", FIELD_MASK);

        HttpEntity<Map<String, Object>> request =
                new HttpEntity<>(body, headers);

        try {
            System.out.println("Consultando Google Routes API...");

            ResponseEntity<String> response = restTemplate.exchange(
                    ROUTES_URL,
                    HttpMethod.POST,
                    request,
                    String.class
            );

            System.out.println(
                    "Google Routes API retornou HTTP " +
                            response.getStatusCode().value()
            );

            String resposta = response.getBody();

            if (resposta == null || resposta.isBlank()) {
                System.err.println("Google Routes API retornou resposta vazia.");

                return ResponseEntity
                        .status(HttpStatus.BAD_GATEWAY)
                        .body("""
                                {"error":"A Routes API retornou uma resposta vazia"}
                                """);
            }

            return ResponseEntity
                    .status(response.getStatusCode())
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(resposta);

        } catch (HttpStatusCodeException e) {

            System.err.println(
                    "Erro na Routes API. HTTP " +
                            e.getStatusCode().value()
            );

            System.err.println(
                    "Detalhes da Routes API: " +
                            e.getResponseBodyAsString()
            );

            return ResponseEntity
                    .status(HttpStatus.BAD_GATEWAY)
                    .body("""
                            {"error":"A Routes API não conseguiu calcular a rota"}
                            """);

        } catch (RestClientException e) {

            System.err.println(
                    "Falha de comunicação com a Routes API: " +
                            e.getMessage()
            );

            return ResponseEntity
                    .status(HttpStatus.BAD_GATEWAY)
                    .body("""
                            {"error":"Não foi possível consultar a Routes API"}
                            """);
        }
    }
}
