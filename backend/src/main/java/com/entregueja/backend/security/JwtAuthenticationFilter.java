
package com.entregueja.backend.security;

import com.entregueja.backend.service.JwtService;

import io.jsonwebtoken.JwtException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.stereotype.Component;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;

    public JwtAuthenticationFilter(
            JwtService jwtService
    ) {
        this.jwtService = jwtService;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {

        String authorization = request.getHeader("Authorization");

        if (authorization != null
                && authorization.startsWith("Bearer ")) {

            String token = authorization.substring(7);

            try {
                Long contaId = jwtService.validarToken(token);
                String tipoConta = jwtService.obterTipoConta(token);

                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(
                                tipoConta + ":" + contaId,
                                null,
                                List.of(
                                        new SimpleGrantedAuthority(tipoConta)
                                )
                        );

                SecurityContextHolder.getContext()
                        .setAuthentication(authentication);

            } catch (
                    JwtException |
                    IllegalArgumentException e
            ) {
                SecurityContextHolder.clearContext();

                response.sendError(
                        HttpServletResponse.SC_UNAUTHORIZED,
                        "Token inválido ou expirado"
                );

                return;
            }
        }

        filterChain.doFilter(request, response);
    }
}
