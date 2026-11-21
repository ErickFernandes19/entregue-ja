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

    @Column(name = "teste_gratuito", nullable = false)
    private boolean testeGratuito = false;

    @Column(name = "mercado_pago_assinatura_id", length = 100)
    private String mercadoPagoAssinaturaId;

    @Column(name = "mercado_pago_plano_id", length = 100)
    private String mercadoPagoPlanoId;

    @Enumerated(EnumType.STRING)
    @Column(name = "plano_agendado", length = 20)
    private Plano planoAgendado;

    @Column(name = "data_troca_agendada")
    private LocalDateTime dataTrocaAgendada;

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

    public boolean isTesteGratuito() {
        return testeGratuito;
    }

    public void setTesteGratuito(boolean testeGratuito) {
        this.testeGratuito = testeGratuito;
    }

    public String getMercadoPagoAssinaturaId() {
        return mercadoPagoAssinaturaId;
    }

    public void setMercadoPagoAssinaturaId(String mercadoPagoAssinaturaId) {
        this.mercadoPagoAssinaturaId = mercadoPagoAssinaturaId;
    }

    public String getMercadoPagoPlanoId() {
        return mercadoPagoPlanoId;
    }

    public void setMercadoPagoPlanoId(String mercadoPagoPlanoId) {
        this.mercadoPagoPlanoId = mercadoPagoPlanoId;
    }

    public Plano getPlanoAgendado() {
        return planoAgendado;
    }

    public void setPlanoAgendado(Plano planoAgendado) {
        this.planoAgendado = planoAgendado;
    }

    public LocalDateTime getDataTrocaAgendada() {
        return dataTrocaAgendada;
    }

    public void setDataTrocaAgendada(LocalDateTime dataTrocaAgendada) {
        this.dataTrocaAgendada = dataTrocaAgendada;
    }
}
