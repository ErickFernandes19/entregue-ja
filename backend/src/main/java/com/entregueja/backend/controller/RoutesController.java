
package com.entregueja.backend.controller;

import com.entregueja.backend.service.RoutesService;
import com.entregueja.backend.service.GeocodingService;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/rotas")
public class RoutesController {

    private final RoutesService routesService;
    private final GeocodingService geocodingService;

    public RoutesController(
            RoutesService routesService,
            GeocodingService geocodingService
    ) {
        this.routesService = routesService;
        this.geocodingService = geocodingService;
    }

    @PostMapping("/calcular")
    public ResponseEntity<String> calcularRota(
            @RequestBody Map<String, Object> body
    ) {
        return routesService.calcularRota(body);
    }

    @GetMapping("/geocodificar")
    public ResponseEntity<Map<String, Double>> geocodificar(
            @RequestParam String endereco
    ) {
        Map<String, Double> coordenadas =
                geocodingService.buscarCoordenadas(endereco);

        if (coordenadas == null) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok(coordenadas);
    }
}