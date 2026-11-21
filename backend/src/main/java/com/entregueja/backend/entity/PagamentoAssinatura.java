package com.entregueja.backend.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "pagamentos_assinatura", indexes = {
        @Index(name = "idx_pagamento_empresa", columnList = "empresa_id"),
        @Index(name = "idx_pagamento_mercado_pago", columnList = "mercado_pago_pagamento_id"),
        @Index(name = "idx_pagamento_assinatura_mp", columnList = "mercado_pago_assinatura_id"),
        @Index(name = "idx_pagamento_empresa_status", columnList = "empresa_id, status")
}, uniqueConstraints = {
        @UniqueConstraint(name = "uk_pagamento_idempotencia", columnNames = "chave_idempotencia")
})
public class PagamentoAssinatura {

    public enum FormaPagamento {
        PIX, CARTAO
    }

    public enum Status {
        PENDENTE, APROVADO, RECUSADO, CANCELADO, REEMBOLSADO
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "empresa_id", nullable = false)
    private Long empresaId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Assinatura.Plano plano;

    @Enumerated(EnumType.STRING)
    @Column(name = "forma_pagamento", nullable = false, length = 20)
    private FormaPagamento formaPagamento;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Status status = Status.PENDENTE;

    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal valor;

    @Column(name = "mercado_pago_pagamento_id", length = 100, unique = true)
    private String mercadoPagoPagamentoId;

    @Column(name = "mercado_pago_assinatura_id", length = 100)
    private String mercadoPagoAssinaturaId;

    @Column(name = "chave_idempotencia", nullable = false, length = 100)
    private String chaveIdempotencia;

    @Column(name = "data_criacao", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @Column(name = "data_atualizacao", nullable = false)
    private LocalDateTime dataAtualizacao;

    @Column(name = "data_vencimento")
    private LocalDateTime dataVencimento;

    @Column(name = "data_aprovacao")
    private LocalDateTime dataAprovacao;

    public PagamentoAssinatura() {
    }

    @PrePersist
    private void antesDeCriar() {
        LocalDateTime agora = LocalDateTime.now();
        if (dataCriacao == null) dataCriacao = agora;
        dataAtualizacao = agora;
    }

    @PreUpdate
    private void antesDeAtualizar() {
        dataAtualizacao = LocalDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public Long getEmpresaId() {
        return empresaId;
    }

    public void setEmpresaId(Long empresaId) {
        this.empresaId = empresaId;
    }

    public Assinatura.Plano getPlano() {
        return plano;
    }

    public void setPlano(Assinatura.Plano plano) {
        this.plano = plano;
    }

    public FormaPagamento getFormaPagamento() {
        return formaPagamento;
    }

    public void setFormaPagamento(FormaPagamento formaPagamento) {
        this.formaPagamento = formaPagamento;
    }

    public Status getStatus() {
        return status;
    }

    public void setStatus(Status status) {
        this.status = status;
    }

    public BigDecimal getValor() {
        return valor;
    }

    public void setValor(BigDecimal valor) {
        this.valor = valor;
    }

    public String getMercadoPagoPagamentoId() {
        return mercadoPagoPagamentoId;
    }

    public void setMercadoPagoPagamentoId(String mercadoPagoPagamentoId) {
        this.mercadoPagoPagamentoId = mercadoPagoPagamentoId;
    }

    public String getMercadoPagoAssinaturaId() {
        return mercadoPagoAssinaturaId;
    }

    public void setMercadoPagoAssinaturaId(String mercadoPagoAssinaturaId) {
        this.mercadoPagoAssinaturaId = mercadoPagoAssinaturaId;
    }

    public String getChaveIdempotencia() {
        return chaveIdempotencia;
    }

    public void setChaveIdempotencia(String chaveIdempotencia) {
        this.chaveIdempotencia = chaveIdempotencia;
    }

    public LocalDateTime getDataCriacao() {
        return dataCriacao;
    }

    public LocalDateTime getDataAtualizacao() {
        return dataAtualizacao;
    }

    public LocalDateTime getDataVencimento() {
        return dataVencimento;
    }

    public void setDataVencimento(LocalDateTime dataVencimento) {
        this.dataVencimento = dataVencimento;
    }

    public LocalDateTime getDataAprovacao() {
        return dataAprovacao;
    }

    public void setDataAprovacao(LocalDateTime dataAprovacao) {
        this.dataAprovacao = dataAprovacao;
    }
}
