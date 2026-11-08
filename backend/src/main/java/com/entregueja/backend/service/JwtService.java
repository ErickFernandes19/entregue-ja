
package com.entregueja.backend.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;

@Service
public class JwtService {

    private final SecretKey chave;

    private static final long DURACAO_TOKEN = 24 * 60 * 60;

    public JwtService(
            @Value("${jwt.secret}") String segredo
    ) {
        if (segredo.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalArgumentException(
                    "JWT_SECRET precisa ter pelo menos 32 bytes"
            );
        }

        this.chave = Keys.hmacShaKeyFor(
                segredo.getBytes(StandardCharsets.UTF_8)
        );
    }


    public String gerarToken(Long contaId, String tipoConta) {

        if (contaId == null) {
            throw new IllegalArgumentException(
                    "ID da conta é obrigatório"
            );
        }

        if (!"EMPRESA".equals(tipoConta)
                && !"ENTREGADOR".equals(tipoConta)) {
            throw new IllegalArgumentException(
                    "Tipo de conta inválido"
            );
        }

        Instant agora = Instant.now();

        return Jwts.builder()
                .subject(contaId.toString())
                .claim("tipo", tipoConta)
                .issuedAt(Date.from(agora))
                .expiration(Date.from(
                        agora.plusSeconds(DURACAO_TOKEN)
                ))
                .signWith(chave)
                .compact();
    }


    public Long validarToken(String token) {
        Claims claims = obterClaims(token);

        validarTipoConta(claims);

        return Long.valueOf(claims.getSubject());
    }


    public String obterTipoConta(String token) {
        Claims claims = obterClaims(token);

        return validarTipoConta(claims);
    }


    private Claims obterClaims(String token) {
        return Jwts.parser()
                .verifyWith(chave)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    private String validarTipoConta(Claims claims) {
        String tipoConta = claims.get("tipo", String.class);

        if (!"EMPRESA".equals(tipoConta)
                && !"ENTREGADOR".equals(tipoConta)) {
            throw new IllegalArgumentException(
                    "Token sem tipo de conta válido"
            );
        }

        return tipoConta;
    }
}
