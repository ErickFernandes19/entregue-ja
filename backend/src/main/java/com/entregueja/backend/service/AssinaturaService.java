package com.entregueja.backend.service;

import com.entregueja.backend.entity.Assinatura;
import com.entregueja.backend.entity.Empresa;
import com.entregueja.backend.entity.Usuario;
import com.entregueja.backend.repository.AssinaturaRepository;
import com.entregueja.backend.repository.EmpresaRepository;
import com.entregueja.backend.repository.UsuarioRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Service
public class AssinaturaService {

    private final AssinaturaRepository assinaturaRepository;
    private final UsuarioRepository usuarioRepository;
    private final EmpresaRepository empresaRepository;
    private final EntityManager entityManager;

    public AssinaturaService(
            AssinaturaRepository assinaturaRepository,
            UsuarioRepository usuarioRepository,
            EmpresaRepository empresaRepository,
            EntityManager entityManager
    ) {
        this.assinaturaRepository = assinaturaRepository;
        this.usuarioRepository = usuarioRepository;
        this.empresaRepository = empresaRepository;
        this.entityManager = entityManager;
    }

    @Transactional(readOnly = true)
    public Optional<Assinatura> buscarAtiva(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        return assinaturaRepository.findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                tipoConta, contaId, Assinatura.Status.ATIVA
        );
    }

    @Transactional(readOnly = true)
    public List<Assinatura> listarHistorico(Assinatura.TipoConta tipoConta, Long contaId) {
        validarConta(tipoConta, contaId);
        return assinaturaRepository.findByTipoContaAndContaIdOrderByIdDesc(tipoConta, contaId);
    }

    @Transactional
    public Assinatura obterOuCriarGratuita(Assinatura.TipoConta tipoConta, Long contaId) {
        validarIdentificadores(tipoConta, contaId);
        bloquearConta(tipoConta, contaId);

        Optional<Assinatura> ativa = assinaturaRepository
                .findFirstByTipoContaAndContaIdAndStatusOrderByIdDesc(
                        tipoConta, contaId, Assinatura.Status.ATIVA
                );

        if (ativa.isPresent()) {
            return ativa.get();
        }

        Assinatura assinatura = new Assinatura();
        assinatura.setTipoConta(tipoConta);
        assinatura.setContaId(contaId);
        assinatura.setPlano(Assinatura.Plano.GRATUITO);
        assinatura.setStatus(Assinatura.Status.ATIVA);
        assinatura.setDataInicio(LocalDateTime.now());
        assinatura.setDataVencimento(null);
        assinatura.setRenovacaoAutomatica(false);

        return assinaturaRepository.save(assinatura);
    }

    private void bloquearConta(Assinatura.TipoConta tipoConta, Long contaId) {
        Object conta = switch (tipoConta) {
            case ENTREGADOR -> entityManager.find(Usuario.class, contaId, LockModeType.PESSIMISTIC_WRITE);
            case EMPRESA -> entityManager.find(Empresa.class, contaId, LockModeType.PESSIMISTIC_WRITE);
        };

        if (conta == null) {
            throw new IllegalArgumentException("Conta não encontrada.");
        }
    }

    private void validarConta(Assinatura.TipoConta tipoConta, Long contaId) {
        validarIdentificadores(tipoConta, contaId);

        boolean existe = switch (tipoConta) {
            case ENTREGADOR -> usuarioRepository.existsById(contaId);
            case EMPRESA -> empresaRepository.existsById(contaId);
        };

        if (!existe) {
            throw new IllegalArgumentException("Conta não encontrada.");
        }
    }

    private void validarIdentificadores(Assinatura.TipoConta tipoConta, Long contaId) {
        if (tipoConta == null) {
            throw new IllegalArgumentException("Tipo de conta é obrigatório.");
        }
        if (contaId == null || contaId <= 0) {
            throw new IllegalArgumentException("Identificador da conta é inválido.");
        }
    }
}
