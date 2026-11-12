
package com.entregueja.backend.service;

import com.entregueja.backend.entity.DispositivoFcm;
import com.entregueja.backend.entity.Notificacao;
import com.entregueja.backend.repository.DispositivoFcmRepository;
import com.entregueja.backend.repository.NotificacaoRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Locale;
import java.util.Optional;

@Service
public class NotificacaoService {

    private final NotificacaoRepository notificacaoRepository;
    private final DispositivoFcmRepository dispositivoFcmRepository;

    public NotificacaoService(
            NotificacaoRepository notificacaoRepository,
            DispositivoFcmRepository dispositivoFcmRepository
    ) {
        this.notificacaoRepository = notificacaoRepository;
        this.dispositivoFcmRepository = dispositivoFcmRepository;
    }

    private String validarTipoConta(String tipoConta) {
        if (tipoConta == null) {
            throw new IllegalArgumentException("Tipo de conta inválido");
        }

        String tipo = tipoConta.trim().toUpperCase(Locale.ROOT);

        if (!tipo.equals("ENTREGADOR") && !tipo.equals("EMPRESA")) {
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
    public Notificacao criarNotificacao(
            String tipoConta,
            Long contaId,
            String tipo,
            String titulo,
            String mensagem,
            Long entregaId
    ) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        if (tipo == null || tipo.isBlank() || tipo.trim().length() > 60
                || titulo == null || titulo.isBlank() || titulo.trim().length() > 160
                || mensagem == null || mensagem.isBlank() || mensagem.trim().length() > 1000) {
            throw new IllegalArgumentException("Dados da notificação inválidos");
        }

        if (entregaId != null && entregaId <= 0) {
            throw new IllegalArgumentException("Entrega inválida");
        }

        Notificacao notificacao = new Notificacao();
        notificacao.setTipoConta(destinatario);
        notificacao.setContaId(contaId);
        notificacao.setTipo(tipo.trim().toUpperCase(Locale.ROOT));
        notificacao.setTitulo(titulo.trim());
        notificacao.setMensagem(mensagem.trim());
        notificacao.setEntregaId(entregaId);

        return notificacaoRepository.save(notificacao);
    }

    @Transactional(readOnly = true)
    public Page<Notificacao> listar(
            String tipoConta,
            Long contaId,
            int pagina,
            int tamanho
    ) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        int paginaSegura = Math.max(0, pagina);
        int tamanhoSeguro = Math.max(1, Math.min(tamanho, 50));

        return notificacaoRepository.findByTipoContaAndContaId(
                destinatario,
                contaId,
                PageRequest.of(
                        paginaSegura,
                        tamanhoSeguro,
                        Sort.by(Sort.Direction.DESC, "criadaEm")
                )
        );
    }

    @Transactional(readOnly = true)
    public long contarNaoLidas(String tipoConta, Long contaId) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        return notificacaoRepository.countByTipoContaAndContaIdAndLidaFalse(
                destinatario,
                contaId
        );
    }

    @Transactional
    public boolean marcarComoLida(
            Long notificacaoId,
            String tipoConta,
            Long contaId
    ) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        if (notificacaoId == null || notificacaoId <= 0) {
            return false;
        }

        Optional<Notificacao> encontrada =
                notificacaoRepository.findByIdAndTipoContaAndContaId(
                        notificacaoId,
                        destinatario,
                        contaId
                );

        if (encontrada.isEmpty()) {
            return false;
        }

        Notificacao notificacao = encontrada.get();

        if (!notificacao.isLida()) {
            notificacao.setLida(true);
            notificacaoRepository.save(notificacao);
        }

        return true;
    }

    @Transactional
    public void registrarDispositivo(
            String tipoConta,
            Long contaId,
            String token,
            String plataforma
    ) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        if (token == null || token.isBlank()
                || token.trim().length() > 2048) {
            throw new IllegalArgumentException("Token FCM inválido");
        }

        String plataformaNormalizada = plataforma == null
                ? "ANDROID"
                : plataforma.trim().toUpperCase(Locale.ROOT);

        if (!plataformaNormalizada.equals("ANDROID")) {
            throw new IllegalArgumentException("Plataforma não suportada");
        }

        String tokenNormalizado = token.trim();

        DispositivoFcm dispositivo = dispositivoFcmRepository
                .findByToken(tokenNormalizado)
                .orElseGet(DispositivoFcm::new);

        dispositivo.setTipoConta(destinatario);
        dispositivo.setContaId(contaId);
        dispositivo.setToken(tokenNormalizado);
        dispositivo.setPlataforma(plataformaNormalizada);

        dispositivoFcmRepository.save(dispositivo);
    }

    @Transactional
    public boolean removerDispositivo(
            String tipoConta,
            Long contaId,
            String token
    ) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        if (token == null || token.isBlank()) {
            return false;
        }

        return dispositivoFcmRepository.deleteByTokenAndTipoContaAndContaId(
                token.trim(),
                destinatario,
                contaId
        ) > 0;
    }

    @Transactional(readOnly = true)
    public List<String> listarTokens(String tipoConta, Long contaId) {
        String destinatario = validarTipoConta(tipoConta);
        validarContaId(contaId);

        return dispositivoFcmRepository
                .findByTipoContaAndContaId(destinatario, contaId)
                .stream()
                .map(DispositivoFcm::getToken)
                .filter(token -> token != null && !token.isBlank())
                .map(String::trim)
                .distinct()
                .toList();
    }
}
