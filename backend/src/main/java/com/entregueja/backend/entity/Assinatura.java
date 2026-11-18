package com.entregueja.backend.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "assinaturas", indexes = {
        @Index(name = "idx_assinatura_conta", columnList = "tipo_conta, conta_id")
})
public class Assinatura {

    public enum TipoConta {
        ENTREGADOR, EMPRESA
    }

    public enum Plano {
        GRATUITO, ESSENCIAL, PROFISSIONAL
    }

    public enum Status {
        ATIVA, PENDENTE, CANCELADA, EXPIRADA
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "tipo_conta", nullable = false, length = 20)
    private TipoConta tipoConta;

    @Column(name = "conta_id", nullable = false)
    private Long contaId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Plano plano = Plano.GRATUITO;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Status status = Status.ATIVA;

    @Column(name = "data_inicio")
    private LocalDateTime dataInicio;

    @Column(name = "data_vencimento")
    private LocalDateTime dataVencimento;

    @Column(name = "renovacao_automatica", nullable = false)
    private boolean renovacaoAutomatica = false;

    public Assinatura() {
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public TipoConta getTipoConta() {
        return tipoConta;
    }

    public void setTipoConta(TipoConta tipoConta) {
        this.tipoConta = tipoConta;
    }

    public Long getContaId() {
        return contaId;
    }

    public void setContaId(Long contaId) {
        this.contaId = contaId;
    }

    public Plano getPlano() {
        return plano;
    }

    public void setPlano(Plano plano) {
        this.plano = plano;
    }

    public Status getStatus() {
        return status;
    }

    public void setStatus(Status status) {
        this.status = status;
    }

    public LocalDateTime getDataInicio() {
        return dataInicio;
    }

    public void setDataInicio(LocalDateTime dataInicio) {
        this.dataInicio = dataInicio;
    }

    public LocalDateTime getDataVencimento() {
        return dataVencimento;
    }

    public void setDataVencimento(LocalDateTime dataVencimento) {
        this.dataVencimento = dataVencimento;
    }

    public boolean isRenovacaoAutomatica() {
        return renovacaoAutomatica;
    }

    public void setRenovacaoAutomatica(boolean renovacaoAutomatica) {
        this.renovacaoAutomatica = renovacaoAutomatica;
    }
}
