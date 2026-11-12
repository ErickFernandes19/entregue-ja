
package com.entregueja.backend.service;

import com.entregueja.backend.entity.PreferenciaNotificacao;
import com.entregueja.backend.repository.PreferenciaNotificacaoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;

@Service
public class PreferenciaNotificacaoService {

    private final PreferenciaNotificacaoRepository repository;

    public PreferenciaNotificacaoService(
            PreferenciaNotificacaoRepository repository
    ) {
        this.repository = repository;
    }

    private String validarTipoConta(String tipoConta) {
        if (tipoConta == null) {
            throw new IllegalArgumentException("Tipo de conta inválido");
        }

        String tipo = tipoConta.trim().toUpperCase(Locale.ROOT);

        if (!tipo.equals("EMPRESA") && !tipo.equals("ENTREGADOR")) {
            throw new IllegalArgumentException("Tipo de conta inválido");
        }

        return tipo;
    }

    private void validarContaId(Long contaId) {
        if (contaId == null || contaId <= 0) {
            throw new IllegalArgumentException("Conta inválida");
        }
    }

    @Transactional
    public PreferenciaNotificacao buscar(String tipoConta, Long contaId) {
        String tipo = validarTipoConta(tipoConta);
        validarContaId(contaId);

        return repository.findByTipoContaAndContaId(tipo, contaId)
                .orElseGet(() -> repository.save(
                        new PreferenciaNotificacao(tipo, contaId)
                ));
    }

    @Transactional
    public PreferenciaNotificacao atualizar(
            String tipoConta,
            Long contaId,
            PreferenciaNotificacao dados
    ) {
        if (dados == null) {
            throw new IllegalArgumentException("Preferências inválidas");
        }

        PreferenciaNotificacao preferencias = buscar(tipoConta, contaId);

        preferencias.setEntregaConcluida(dados.isEntregaConcluida());
        preferencias.setEntregaCancelada(dados.isEntregaCancelada());
        preferencias.setEntregaNaoRealizada(dados.isEntregaNaoRealizada());
        preferencias.setNovoEntregador(dados.isNovoEntregador());
        preferencias.setSolicitacoes(dados.isSolicitacoes());
        preferencias.setNovaEntrega(dados.isNovaEntrega());
        preferencias.setVinculos(dados.isVinculos());
        preferencias.setSons(dados.isSons());
        preferencias.setVibracao(dados.isVibracao());

        return repository.save(preferencias);
    }

    @Transactional(readOnly = true)
    public boolean permiteNotificacao(
            String tipoConta,
            Long contaId,
            String tipoNotificacao
    ) {
        String tipo = validarTipoConta(tipoConta);
        validarContaId(contaId);

        if (tipoNotificacao == null || tipoNotificacao.isBlank()) {
            return false;
        }

        PreferenciaNotificacao preferencias = repository
                .findByTipoContaAndContaId(tipo, contaId)
                .orElse(null);

        if (preferencias == null) {
            return true;
        }

        String notificacao = tipoNotificacao.trim().toUpperCase(Locale.ROOT);

        if ("EMPRESA".equals(tipo)) {
            return switch (notificacao) {
                case "ENTREGA_CONCLUIDA" ->
                        preferencias.isEntregaConcluida();

                case "ENTREGA_CANCELADA" ->
                        preferencias.isEntregaCancelada();

                case "ENTREGA_NAO_REALIZADA" ->
                        preferencias.isEntregaNaoRealizada();

                case "VINCULO_ACEITO" ->
                        preferencias.isNovoEntregador();

                case "VINCULO_RECUSADO",
                     "SOLICITACAO_VINCULO",
                     "SOLICITACAO_CANCELADA" ->
                        preferencias.isSolicitacoes();

                case "NOVA_ENTREGA",
                     "ENTREGA_ATRIBUIDA" ->
                        preferencias.isNovaEntrega();

                case "CONVITE_VINCULO",
                     "VINCULO_PENDENTE",
                     "VINCULO_ENCERRADO" ->
                        preferencias.isVinculos();

                default -> true;
            };
        }

        return switch (notificacao) {
            case "NOVA_ENTREGA",
                 "ENTREGA_ATRIBUIDA" ->
                    preferencias.isNovaEntrega();

            case "ENTREGA_CONCLUIDA",
                 "ENTREGA_CANCELADA",
                 "ENTREGA_NAO_REALIZADA" ->
                    preferencias.isEntregaConcluida()
                            && preferencias.isEntregaCancelada()
                            && preferencias.isEntregaNaoRealizada();

            case "SOLICITACAO_VINCULO",
                 "SOLICITACAO_CANCELADA",
                 "VINCULO_ACEITO",
                 "VINCULO_RECUSADO",
                 "CONVITE_VINCULO",
                 "VINCULO_PENDENTE",
                 "VINCULO_ENCERRADO" ->
                    preferencias.isVinculos();

            default -> true;
        };
    }
}
