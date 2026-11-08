
package com.entregueja.backend.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.List;
import java.util.Map;

@Service
public class GeocodingService {

    private static final String GEOCODING_URL =
            "https://maps.googleapis.com/maps/api/geocode/json";

    @Value("${google.routes.api-key}")
    private String apiKey;

    private final RestTemplate restTemplate = new RestTemplate();

    public Map<String, Double> buscarCoordenadas(String endereco) {

        if (endereco == null || endereco.isBlank()) {
            return null;
        }

        if (apiKey == null || apiKey.isBlank()) {
            throw new IllegalStateException(
                    "Chave Google não configurada no backend"
            );
        }

        URI uri = UriComponentsBuilder
                .fromUriString(GEOCODING_URL)
                .queryParam("address", endereco.trim())
                .queryParam("region", "br")
                .queryParam("language", "pt-BR")
                .queryParam("key", apiKey)
                .encode()
                .build()
                .toUri();

        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> resposta =
                    restTemplate.getForObject(uri, Map.class);

            if (resposta == null) {
                System.err.println(
                        "Google Geocoding retornou uma resposta vazia."
                );
                return null;
            }

            String status = String.valueOf(
                    resposta.get("status")
            );

            if (!"OK".equals(status)) {

                String mensagemErro = String.valueOf(
                        resposta.getOrDefault(
                                "error_message",
                                "Nenhuma mensagem adicional fornecida."
                        )
                );

                System.err.println(
                        "Google Geocoding retornou: " + status
                );

                System.err.println(
                        "Motivo informado pelo Google: " + mensagemErro
                );

                return null;
            }

            Object resultadosObj = resposta.get("results");

            if (!(resultadosObj instanceof List<?> resultados)
                    || resultados.isEmpty()) {
                return null;
            }

            if (!(resultados.get(0) instanceof Map<?, ?> primeiro)) {
                return null;
            }

            if (!(primeiro.get("geometry") instanceof Map<?, ?> geometry)) {
                return null;
            }

            if (!(geometry.get("location") instanceof Map<?, ?> location)) {
                return null;
            }

            Object latObj = location.get("lat");
            Object lngObj = location.get("lng");

            if (!(latObj instanceof Number lat)
                    || !(lngObj instanceof Number lng)) {
                return null;
            }

            return Map.of(
                    "lat", lat.doubleValue(),
                    "lng", lng.doubleValue()
            );

        } catch (RestClientException e) {
            System.err.println(
                    "Erro ao consultar Google Geocoding: "
                            + e.getMessage()
            );
            return null;
        }
    }
}
