import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entrega_model.dart';
import '../providers/entregas_provider.dart';
import '../services/configuracoes_service.dart';
import '../theme/app_colors.dart';

class RelatorioPage extends StatefulWidget {
  const RelatorioPage({super.key});

  @override
  State<RelatorioPage> createState() => _RelatorioPageState();
}

class _RelatorioPageState extends State<RelatorioPage> {
  String veiculo = 'Moto';
  double consumoMedio = 0;
  double precoCombustivel = 0;
  int capacidade = 0;

  bool carregando = true;
  bool gerandoArquivo = false;

  final Set<String> statusSelecionados = {
    'PENDENTE',
    'EM_ROTA',
    'ENTREGUE',
    'NAO_ENTREGUE',
  };

  bool incluirVeiculo = true;
  bool incluirResumo = true;
  bool incluirFinanceiro = true;
  bool incluirDetalhes = true;

  @override
  void initState() {
    super.initState();
    carregarConfiguracoes();
  }

  Future<void> carregarConfiguracoes() async {
    final veiculoSalvo = await ConfiguracoesService.buscarVeiculo();

    final capacidadeSalva = await ConfiguracoesService.buscarCapacidade();

    final consumo = await ConfiguracoesService.buscarConsumoMedio();

    final preco = await ConfiguracoesService.buscarPrecoCombustivel();

    if (!mounted) return;

    setState(() {
      veiculo = veiculoSalvo ?? 'Moto';

      capacidade = int.tryParse(capacidadeSalva ?? '') ?? 0;

      consumoMedio = double.tryParse((consumo ?? '').replaceAll(',', '.')) ?? 0;

      precoCombustivel =
          double.tryParse((preco ?? '').replaceAll(',', '.')) ?? 0;

      carregando = false;
    });
  }

  double distanciaMediaPorEntrega() {
    switch (veiculo) {
      case 'Moto':
        return 4.0;

      case 'Hatch':
      case 'Sedan':
        return 5.0;

      case 'SUV':
        return 5.5;

      case 'Pickup':
      case 'Van':
        return 6.0;

      case 'Caminhão Pequeno':
        return 7.0;

      case 'Caminhão Grande':
        return 8.0;

      default:
        return 5.0;
    }
  }

  String textoStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return 'Entregue';

      case 'EM_ROTA':
        return 'Em rota';

      case 'NAO_ENTREGUE':
        return 'Não entregue';

      case 'PENDENTE':
      default:
        return 'Pendente';
    }
  }

  Color corStatus(String status) {
    switch (status) {
      case 'ENTREGUE':
        return AppColors.success;

      case 'EM_ROTA':
        return Colors.blue;

      case 'NAO_ENTREGUE':
        return AppColors.error;

      case 'PENDENTE':
      default:
        return AppColors.warning;
    }
  }

  List<EntregaModel> entregasFiltradas(List<EntregaModel> todas) {
    return todas.where((entrega) {
      if (entrega.status == 'CANCELADA') {
        return false;
      }

      return statusSelecionados.contains(entrega.status);
    }).toList();
  }

  Map<String, dynamic> calcularDados(List<EntregaModel> entregas) {
    final entregues = entregas.where((e) => e.status == 'ENTREGUE').toList();

    final pendentes = entregas.where((e) => e.status == 'PENDENTE').toList();

    final emRota = entregas.where((e) => e.status == 'EM_ROTA').toList();

    final naoEntregues = entregas
        .where((e) => e.status == 'NAO_ENTREGUE')
        .toList();

    final receitaTotal = entregues.fold<double>(
      0,
      (total, entrega) => total + entrega.valor,
    );

    final distanciaKm = entregues.length * distanciaMediaPorEntrega();

    final litrosUsados = consumoMedio > 0 ? distanciaKm / consumoMedio : 0.0;

    final gastoCombustivel = litrosUsados * precoCombustivel;

    final lucroLiquido = receitaTotal - gastoCombustivel;

    return {
      'total': entregas.length,
      'entregues': entregues.length,
      'pendentes': pendentes.length,
      'emRota': emRota.length,
      'naoEntregues': naoEntregues.length,
      'receita': receitaTotal,
      'distancia': distanciaKm,
      'litros': litrosUsados,
      'combustivel': gastoCombustivel,
      'lucro': lucroLiquido,
    };
  }

  Future<void> abrirFiltros() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget statusCheckbox({
              required String status,
              required String texto,
            }) {
              return CheckboxListTile(
                value: statusSelecionados.contains(status),
                title: Text(texto),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (valor) {
                  setModalState(() {
                    if (valor == true) {
                      statusSelecionados.add(status);
                    } else {
                      statusSelecionados.remove(status);
                    }
                  });

                  setState(() {});
                },
              );
            }

            Widget opcaoRelatorio({
              required String titulo,
              required bool valor,
              required ValueChanged<bool> onChanged,
            }) {
              return SwitchListTile(
                title: Text(titulo),
                value: valor,
                onChanged: (novoValor) {
                  setModalState(() {
                    onChanged(novoValor);
                  });

                  setState(() {});
                },
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const Text(
                      'Configurar relatório',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Escolha quais informações serão consideradas ao imprimir ou gerar o Excel.',
                    ),

                    const SizedBox(height: 22),

                    const Text(
                      'Status das entregas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    statusCheckbox(status: 'PENDENTE', texto: 'Pendentes'),

                    statusCheckbox(status: 'EM_ROTA', texto: 'Em rota'),

                    statusCheckbox(status: 'ENTREGUE', texto: 'Entregues'),

                    statusCheckbox(
                      status: 'NAO_ENTREGUE',
                      texto: 'Não entregues',
                    ),

                    const Divider(),

                    const Text(
                      'Conteúdo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    opcaoRelatorio(
                      titulo: 'Veículo e capacidade',
                      valor: incluirVeiculo,
                      onChanged: (valor) {
                        incluirVeiculo = valor;
                      },
                    ),

                    opcaoRelatorio(
                      titulo: 'Resumo das entregas',
                      valor: incluirResumo,
                      onChanged: (valor) {
                        incluirResumo = valor;
                      },
                    ),

                    opcaoRelatorio(
                      titulo: 'Custos e ganhos',
                      valor: incluirFinanceiro,
                      onChanged: (valor) {
                        incluirFinanceiro = valor;
                      },
                    ),

                    opcaoRelatorio(
                      titulo: 'Detalhes das entregas',
                      valor: incluirDetalhes,
                      onChanged: (valor) {
                        incluirDetalhes = valor;
                      },
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  pw.Widget linhaPdf(String titulo, String valor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(titulo),
          pw.Text(valor, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<Uint8List> criarPdf(List<EntregaModel> entregas) async {
    final dados = calcularDados(entregas);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Text(
              'Entregue Já',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),

            pw.SizedBox(height: 4),

            pw.Text(
              'Relatório de Entregas',
              style: const pw.TextStyle(fontSize: 18),
            ),

            pw.SizedBox(height: 6),

            pw.Text(
              'Gerado em: '
              '${DateTime.now().day.toString().padLeft(2, '0')}/'
              '${DateTime.now().month.toString().padLeft(2, '0')}/'
              '${DateTime.now().year}',
            ),

            pw.SizedBox(height: 20),

            if (incluirVeiculo) ...[
              pw.Text(
                'Veículo',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Divider(),

              linhaPdf('Tipo', veiculo),

              linhaPdf(
                'Capacidade',
                capacidade > 0 ? '$capacidade kg' : 'Não definida',
              ),

              pw.SizedBox(height: 16),
            ],

            if (incluirResumo) ...[
              pw.Text(
                'Resumo das entregas',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Divider(),

              linhaPdf('Total', dados['total'].toString()),

              linhaPdf('Pendentes', dados['pendentes'].toString()),

              linhaPdf('Em rota', dados['emRota'].toString()),

              linhaPdf('Entregues', dados['entregues'].toString()),

              linhaPdf('Não entregues', dados['naoEntregues'].toString()),

              pw.SizedBox(height: 16),
            ],

            if (incluirFinanceiro) ...[
              pw.Text(
                'Custos e ganhos',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.Divider(),

              linhaPdf(
                'Distância estimada',
                '${dados['distancia'].toStringAsFixed(1)} km',
              ),

              linhaPdf(
                'Combustível estimado',
                '${dados['litros'].toStringAsFixed(2)} L',
              ),

              linhaPdf('Receita', 'R\$ ${dados['receita'].toStringAsFixed(2)}'),

              linhaPdf(
                'Gasto combustível',
                'R\$ ${dados['combustivel'].toStringAsFixed(2)}',
              ),

              linhaPdf(
                'Lucro líquido',
                'R\$ ${dados['lucro'].toStringAsFixed(2)}',
              ),

              pw.SizedBox(height: 20),
            ],

            if (incluirDetalhes) ...[
              pw.Text(
                'Entregas',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 8),

              pw.TableHelper.fromTextArray(
                headers: const ['ID', 'Cliente', 'Endereço', 'Status', 'Valor'],
                data: entregas.map((e) {
                  return [
                    e.id?.toString() ?? '-',
                    e.cliente,
                    e.endereco,
                    textoStatus(e.status),
                    'R\$ ${e.valor.toStringAsFixed(2)}',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellStyle: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> imprimirRelatorio(List<EntregaModel> entregas) async {
    if (entregas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma entrega encontrada com os filtros selecionados.',
          ),
        ),
      );

      return;
    }

    final bytes = await criarPdf(entregas);

    await Printing.layoutPdf(
      name: 'Relatório Entregue Já',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> gerarExcel(List<EntregaModel> entregas) async {
    if (entregas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhuma entrega encontrada com os filtros selecionados.',
          ),
        ),
      );

      return;
    }

    if (gerandoArquivo) return;

    setState(() {
      gerandoArquivo = true;
    });

    try {
      final dados = calcularDados(entregas);

      final excel = Excel.createExcel();

      final resumo = excel['Resumo'];

      resumo.appendRow([TextCellValue('Relatório Entregue Já')]);

      resumo.appendRow([]);

      if (incluirVeiculo) {
        resumo.appendRow([TextCellValue('Veículo'), TextCellValue(veiculo)]);

        resumo.appendRow([
          TextCellValue('Capacidade de carga'),
          TextCellValue(capacidade > 0 ? '$capacidade kg' : 'Não definida'),
        ]);
      }

      if (incluirResumo) {
        resumo.appendRow([]);

        resumo.appendRow([
          TextCellValue('Indicador'),
          TextCellValue('Quantidade'),
        ]);

        resumo.appendRow([
          TextCellValue('Total de entregas'),
          IntCellValue(dados['total']),
        ]);

        resumo.appendRow([
          TextCellValue('Pendentes'),
          IntCellValue(dados['pendentes']),
        ]);

        resumo.appendRow([
          TextCellValue('Em rota'),
          IntCellValue(dados['emRota']),
        ]);

        resumo.appendRow([
          TextCellValue('Entregues'),
          IntCellValue(dados['entregues']),
        ]);

        resumo.appendRow([
          TextCellValue('Não entregues'),
          IntCellValue(dados['naoEntregues']),
        ]);
      }

      if (incluirFinanceiro) {
        resumo.appendRow([]);

        resumo.appendRow([
          TextCellValue('Distância estimada'),
          TextCellValue('${dados['distancia'].toStringAsFixed(1)} km'),
        ]);

        resumo.appendRow([
          TextCellValue('Combustível estimado'),
          TextCellValue('${dados['litros'].toStringAsFixed(2)} L'),
        ]);

        resumo.appendRow([
          TextCellValue('Receita'),
          DoubleCellValue(dados['receita']),
        ]);

        resumo.appendRow([
          TextCellValue('Gasto combustível'),
          DoubleCellValue(dados['combustivel']),
        ]);

        resumo.appendRow([
          TextCellValue('Lucro líquido'),
          DoubleCellValue(dados['lucro']),
        ]);
      }

      if (incluirDetalhes) {
        final planilha = excel['Entregas'];

        planilha.appendRow([
          TextCellValue('ID'),
          TextCellValue('Cliente'),
          TextCellValue('Endereço'),
          TextCellValue('Status'),
          TextCellValue('Valor'),
          TextCellValue('Observação'),
        ]);

        for (final entrega in entregas) {
          planilha.appendRow([
            TextCellValue(entrega.id?.toString() ?? ''),
            TextCellValue(entrega.cliente),
            TextCellValue(entrega.endereco),
            TextCellValue(textoStatus(entrega.status)),
            DoubleCellValue(entrega.valor),
            TextCellValue(entrega.observacao),
          ]);
        }
      }

      final bytes = excel.save();

      if (bytes == null) {
        throw Exception('Erro ao gerar arquivo Excel');
      }

      final diretorio = await getTemporaryDirectory();

      final arquivo = File(
        '${diretorio.path}/'
        'relatorio_entregue_ja_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );

      await arquivo.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles([
        XFile(arquivo.path),
      ], text: 'Relatório de entregas - Entregue Já');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao gerar Excel: $e')));
    } finally {
      if (mounted) {
        setState(() {
          gerandoArquivo = false;
        });
      }
    }
  }

  Widget cardRelatorio({
    required IconData icon,
    required String titulo,
    required String valor,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);

    final cor = iconColor ?? AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.18)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cor.withOpacity(0.14),
          child: Icon(icon, color: cor),
        ),
        title: Text(titulo),
        trailing: Text(
          valor,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todas = Provider.of<EntregasProvider>(context).entregas;

    final entregas = entregasFiltradas(todas);

    final dados = calcularDados(entregas);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Filtros',
            onPressed: abrirFiltros,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Relatório',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    OutlinedButton.icon(
                      onPressed: abrirFiltros,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Filtrar'),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                Text('${entregas.length} entrega(s) incluída(s)'),

                const SizedBox(height: 22),

                if (incluirVeiculo) ...[
                  cardRelatorio(
                    icon: Icons.directions_car,
                    titulo: 'Veículo',
                    valor: veiculo,
                  ),

                  cardRelatorio(
                    icon: Icons.inventory,
                    titulo: 'Capacidade',
                    valor: capacidade > 0 ? '$capacidade kg' : 'Não definida',
                    iconColor: Colors.orange,
                  ),
                ],

                if (incluirResumo) ...[
                  const SizedBox(height: 8),

                  const Text(
                    'Entregas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  cardRelatorio(
                    icon: Icons.inventory_2,
                    titulo: 'Total',
                    valor: '${dados['total']}',
                  ),

                  cardRelatorio(
                    icon: Icons.pending,
                    titulo: 'Pendentes',
                    valor: '${dados['pendentes']}',
                    iconColor: AppColors.warning,
                  ),

                  cardRelatorio(
                    icon: Icons.local_shipping,
                    titulo: 'Em rota',
                    valor: '${dados['emRota']}',
                    iconColor: Colors.blue,
                  ),

                  cardRelatorio(
                    icon: Icons.check_circle,
                    titulo: 'Entregues',
                    valor: '${dados['entregues']}',
                    iconColor: AppColors.success,
                  ),

                  cardRelatorio(
                    icon: Icons.report_problem,
                    titulo: 'Não entregues',
                    valor: '${dados['naoEntregues']}',
                    iconColor: AppColors.error,
                  ),
                ],

                if (incluirFinanceiro) ...[
                  const SizedBox(height: 8),

                  const Text(
                    'Custos e ganhos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 12),

                  cardRelatorio(
                    icon: Icons.route,
                    titulo: 'Distância estimada',
                    valor: '${dados['distancia'].toStringAsFixed(1)} km',
                    iconColor: Colors.blue,
                  ),

                  cardRelatorio(
                    icon: Icons.local_gas_station,
                    titulo: 'Combustível estimado',
                    valor: '${dados['litros'].toStringAsFixed(2)} L',
                    iconColor: AppColors.error,
                  ),

                  cardRelatorio(
                    icon: Icons.attach_money,
                    titulo: 'Receita',
                    valor: 'R\$ ${dados['receita'].toStringAsFixed(2)}',
                    iconColor: AppColors.success,
                  ),

                  cardRelatorio(
                    icon: Icons.local_gas_station,
                    titulo: 'Gasto combustível',
                    valor: 'R\$ ${dados['combustivel'].toStringAsFixed(2)}',
                    iconColor: AppColors.error,
                  ),

                  cardRelatorio(
                    icon: Icons.trending_up,
                    titulo: 'Lucro líquido',
                    valor: 'R\$ ${dados['lucro'].toStringAsFixed(2)}',
                    iconColor: dados['lucro'] >= 0
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ],

                const SizedBox(height: 26),

                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      imprimirRelatorio(entregas);
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimir / Gerar PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: gerandoArquivo
                        ? null
                        : () {
                            gerarExcel(entregas);
                          },
                    icon: gerandoArquivo
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.table_view),
                    label: Text(gerandoArquivo ? 'Gerando...' : 'Gerar Excel'),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
