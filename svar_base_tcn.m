%% ========================================================================
%  SVAR con identificación mixta: Instrumentos Externos + Restricciones de Signo
%  Método: Cesa-Bianchi & Sokol (2021), implementado en el VAR Toolbox
%  (Cesa-Bianchi) mediante VARopt.ident = 'sign+iv'

addpath(genpath("C:\Users\K21168\Desktop\VARtoolbox"))

%
%  Datos TRIMESTRALES (agregados desde la base mensual original):
%    igae, sub, tasa, exp, tcr : promedio del trimestre
%    mps                       : SUMA del trimestre (instrumento de sorpresas
%                                 de política monetaria; sumar preserva el
%                                 contenido informativo acumulado del
%                                 trimestre, convención estándar en IV de
%                                 alta frecuencia agregada, e.g. Gertler-
%                                 Karadi 2015)
%  Trimestres con menos de 3 meses de datos (bordes de la muestra) fueron
%  descartados en la agregación.
%
%  La actividad (igae) se transforma a BRECHA DEL PRODUCTO mediante
%  log(igae) + filtro HP con lambda = 1600 (estándar para datos TRIMESTRALES,
%  Hodrick-Prescott original / Ravn-Uhlig 2002).
%  El tipo de cambio (diff_ln_tcn) se usa directamente, sin filtro HP.
%
%  Choque de política monetaria  -> identificado con el instrumento externo mps
%  Choques restantes (4)         -> identificados con restricciones de signo,
%                                    condicionales al choque ya fijado por el IV
%
%  ANÁLISIS DE ESTABILIDAD: ventanas MÓVILES ("rolling") de 10 años,
%  comenzando en enero de 2008, desplazándose un año a la vez hasta donde
%  alcancen los datos disponibles. Por construcción las ventanas se
%  traslapan entre sí.
% ========================================================================

clear; clc; close all;

%% 1) Cargar datos
% ------------------------------------------------------------------------
% El archivo trae encabezados: Fecha, igae, sub, tasa, exp, tcr, mps
% Fecha = primer día de cada trimestre (fecha real de Excel).
Ttab = readtable("C:\Users\K21168\Desktop\modelo_expectativas\SVAR\Datos\BaseDatosMensual.xlsx");

dates_dt = datetime(Ttab.Fecha);   % fechas trimestrales
igae     = Ttab.igae;
inf      = Ttab.inf_g;               % inflación (subyacente)
tasa     = Ttab.tasa;              % tasa de interés (equivalente a cetes28)
exp      = Ttab.exp4_g;               % expectativas
diff_ln_tcn  = Ttab.diff_ln_tcn;               % tipo de cambio real (en logaritmos, L_TCR)
mps      = Ttab.mps*-1;               % instrumento externo (monetary policy shock, sumado por trimestre)

T = height(Ttab);

mnem = {'igae','inf','tasa','exp','diff_ln_tcn','mps'};

%% 1.0) Gráfica exploratoria de las series originales
% ------------------------------------------------------------------------
fig_raw = figure('Name','Series originales (trimestral)');
vars_raw  = {igae, inf, tasa, exp, diff_ln_tcn, mps};
names_raw = {'IGAE (nivel)','Inflacion','Tasa de interes', ...
             'Exp. Inflacion','diff_ln_tcn','mps (instrumento)'};
n_raw = numel(vars_raw);

for i = 1:n_raw
    subplot(ceil(n_raw/2), 2, i);
    plot(dates_dt, vars_raw{i}, 'LineWidth', 1.2);
    title(names_raw{i}, 'Interpreter', 'latex');
    xlabel('Fecha'); grid on;
end
sgtitle('Series originale (antes de transformar)', 'Interpreter', 'latex');

if ~exist('graphics', 'dir'); mkdir('graphics'); end
print(fig_raw, '-dpdf', 'graphics/series_originales_trimestral.pdf');

%% 1.1) Brecha del producto y brecha del TCR (log/log + filtro HP, lambda=1600)
% ------------------------------------------------------------------------
lambda_hp = 14400;                  % lambda estándar para frecuencia TRIMESTRAL

% --- Actividad: brecha del producto ---
log_igae  = log(igae);
[igae_trend, igae_cycle] = hpfilter(log_igae, 'Smoothing', lambda_hp);
% Si tu versión de MATLAB usa la sintaxis antigua, sustituye la línea de
% arriba por:  [igae_trend, igae_cycle] = hpfilter(log_igae, lambda_hp);

actividad = igae_cycle;        % brecha en % (log-desviación * 100)
act_label = 'Brecha del producto (igae, filtro HP, \lambda=14400)';
diff_ln_tcn_label = 'diff_ln_tcn';


%% 1.1b) Gráfica de la descomposición HP (tendencia vs. ciclo)
% ------------------------------------------------------------------------
fig_hp = figure('Name','Descomposici\''on HP: IGAE y TCR (trimestral)');

subplot(2,2,1);
plot(dates_dt, log_igae, 'k', dates_dt, igae_trend, 'r--', 'LineWidth', 1.2);
title('log(igae): serie y tendencia HP', 'Interpreter','latex'); grid on;
legend('log(igae)','Tendencia','Location','best');

subplot(2,2,2);
plot(dates_dt, actividad, 'b', 'LineWidth', 1.2); yline(0,'k:');
title(act_label, 'Interpreter','latex'); grid on;


subplot(2,2,3);
plot(dates_dt, diff_ln_tcn, 'b', 'LineWidth', 1.2); yline(0,'k:');
title(diff_ln_tcn_label, 'Interpreter','latex'); grid on;

sgtitle('Descomposici\''on HP ($\lambda=1600$): actividad y TCR', 'Interpreter','latex');
print(fig_hp, '-dpdf', 'graphics/descomposicion_hp_igae_tcr_trimestral.pdf');

%% 1.2) Chequeo de estacionariedad (ADF + KPSS) de todas las series
% ------------------------------------------------------------------------
series_test = {actividad, inf, tasa, exp, diff_ln_tcn, mps};
label_test  = {'Brecha del producto (IGAE)', 'Inflaci\''on (sub)', 'Tasa de inter\''es', ...
               'Exp. Inflaci\''on', 'Brecha del TCR', 'mps (instrumento)'};
name_test   = {'actividad','sub','tasa','exp','brecha_tcr','mps'};

nseries = numel(series_test);
ADF_h  = nan(nseries,1); ADF_p  = nan(nseries,1);
KPSS_h = nan(nseries,1); KPSS_p = nan(nseries,1);

if exist('adftest','file') == 2 && exist('kpsstest','file') == 2
    for i = 1:nseries
        s = series_test{i};
        s_clean = s(~isnan(s));

        [ADF_h(i), ADF_p(i)]   = adftest(s_clean);
        [KPSS_h(i), KPSS_p(i)] = kpsstest(s_clean);

        fprintf('%-14s -> ADF:  h = %d (1=estacionaria), p = %.4f | KPSS: h = %d (0=estacionaria), p = %.4f\n', ...
            name_test{i}, ADF_h(i), ADF_p(i), KPSS_h(i), KPSS_p(i));

        if ADF_h(i) == 0 || KPSS_h(i) == 1
            warning(['La serie "%s" (%s) NO pasa las pruebas de estacionariedad de ' ...
                     'forma concluyente. Revisa la transformaci\''on o considera ' ...
                     'diferenciar/ajustar el filtro.'], name_test{i}, label_test{i});
        end
    end

    % Tabla resumen
    StationarityResults = table(name_test', ADF_h, ADF_p, KPSS_h, KPSS_p, ...
        'VariableNames', {'Serie','ADF_h','ADF_p','KPSS_h','KPSS_p'});
    disp(StationarityResults);

else
    warning(['adftest/kpsstest no disponibles (requieren Econometrics ' ...
              'Toolbox); revisa la estacionariedad de las series manualmente ' ...
              'antes de confiar en los resultados del VAR.']);
end


%% 1.3) Ensamblar X completo
% ------------------------------------------------------------------------
X = [actividad, inf, tasa, exp, diff_ln_tcn];
Xmnem   = {'brecha_igae','inf','tasa','exp','diff_ln_tcn'};
Xvnames = {'Brecha del Producto','Inflacion (sub)','Tasa de interes','Exp. Inflacion','Brecha del TCR'};

nvars = size(X,2);

%% 2) Selección de rezagos (sobre la muestra completa)
% ------------------------------------------------------------------------
%{
pmax = 12;               % 8 trimestres = 2 años a probar; ajusta si quieres más
disp('--- Selección de rezagos (criterios de información, muestra completa) ---')
[lag_AIC, lag_BIC, ~] = VARlag(X, pmax, 1);

fprintf('Rezago óptimo según AIC: %d\n', lag_AIC);
fprintf('Rezago óptimo según BIC: %d\n', lag_BIC);
%}
nlags = 2;               % <-- AJUSTA con base en el resultado de VARlag (4 trim. = 1 año es un punto de partida típico)
detc  = 1;               % 1 = constante


%% 1.4) Dummy COVID: 2020-Q2 y 2020-Q3
% ------------------------------------------------------------------------
% Impulse dummy (no step): vale 1 solo en esos dos trimestres, 0 en el resto.
% Captura el choque atípico de esos dos trimestres sin dejar un "escalón"
% permanente en el resto de la muestra.
DUM_covid = zeros(T,1);
DUM_covid(dates_dt == datetime(2009,1,1) | dates_dt == datetime(2016,11,1) | dates_dt == datetime(2020,4,1) | dates_dt == datetime(2020,5,1)) = 1;

if sum(DUM_covid) ~= 2
    warning(['La dummy COVID no encontró exactamente 2 trimestres (encontró %d). ' ...
             'Revisa que las fechas en dates_dt correspondan al primer día de cada trimestre.'], sum(DUM_covid));
end

%% 3) Definición de las ventanas de muestra (ROLLING, 10 años)
% ------------------------------------------------------------------------
fecha_min_datos = dates_dt(1);
fecha_max_datos = dates_dt(T);

% --- Parámetros de la ventana móvil --------------------------------------
ventana_anios = 10;                    % ancho de cada ventana (años)
paso_anios    = 4;                     % desplazamiento entre ventanas (años)
ventana_ini0  = datetime(2008,1,1);    % inicio de la primera ventana

% Genera ventanas [ini_k, fin_k] de `ventana_anios` años, empezando en
% ventana_ini0 y desplazándose `paso_anios` años a la vez, mientras el fin
% de la ventana no exceda la última fecha disponible en los datos.
ventana_ini = datetime.empty(0,1);
ventana_fin = datetime.empty(0,1);
ini_k = ventana_ini0;
while true
    fin_k = ini_k + calyears(ventana_anios) - caldays(1);
    if fin_k > fecha_max_datos
        break
    end
    ventana_ini(end+1,1) = ini_k;   %#ok<SAGROW>
    ventana_fin(end+1,1) = fin_k;   %#ok<SAGROW>
    ini_k = ini_k + calyears(paso_anios);
end
n_ventanas = numel(ventana_ini);

if n_ventanas == 0
    error(['No se pudo formar ni una ventana de %d años a partir de %s: ' ...
           'los datos terminan en %s.'], ventana_anios, ...
           datestr(ventana_ini0,'yyyy-mm'), datestr(fecha_max_datos,'yyyy-mm'));
end

ventana_lbl = cell(n_ventanas,1);
for k = 1:n_ventanas
    ventana_lbl{k} = sprintf('%d-%d', year(ventana_ini(k)), year(ventana_fin(k)));
end

idx = cell(n_ventanas,1);
for k = 1:n_ventanas
    idx{k} = find(dates_dt >= ventana_ini(k) & dates_dt <= ventana_fin(k));
    if isempty(idx{k})
        error('Ventana %s no tiene observaciones dentro del rango de datos disponible.', ventana_lbl{k});
    end
end

fprintf('\n--- Ventanas móviles de %d años (paso %d año(s)), trimestral ---\n', ventana_anios, paso_anios);
for k = 1:n_ventanas
    fprintf('Ventana %d/%d (%s): %s a %s, n = %d trimestres\n', ...
        k, n_ventanas, ventana_lbl{k}, datestr(dates_dt(idx{k}(1)), 'yyyy-mm'), ...
        datestr(dates_dt(idx{k}(end)), 'yyyy-mm'), length(idx{k}));
end

for k = 1:n_ventanas
    for j = (k+1):n_ventanas
        n_trasl = length(intersect(idx{k}, idx{j}));
        if n_trasl > 0
            fprintf('Nota: %d trimestres están presentes tanto en la ventana %d como en la %d.\n', ...
                n_trasl, k, j);
        end
    end
end

% Chequeo de tamaño de muestra vs. parámetros estimados
n_param_por_ecuacion = nvars*nlags + detc;
for k = 1:n_ventanas
    if length(idx{k}) < 10*n_param_por_ecuacion
        warning(['Ventana %d (%s) tiene solo %d trimestres frente a ~%d parámetros por ecuación ' ...
                 '(regla informal: se recomienda >= 10x). Resultados potencialmente poco confiables.'], ...
                 k, ventana_lbl{k}, length(idx{k}), n_param_por_ecuacion);
    end
end

%% 4) Opciones generales del VAR (compartidas por todas las ventanas)
% ------------------------------------------------------------------------
VARopt = VARoption;
VARopt.vnames    = Xvnames;
VARopt.mnem      = Xmnem;
VARopt.nsteps    = 60;         % horizonte de los IRF: 20 TRIMESTRES (~5 años)
VARopt.frequency = 'm';        % trimestral
VARopt.impact    = 0;
VARopt.pctg      = 68;
VARopt.method    = 'wild';
VARopt.inference = 1;
VARopt.ndraws    = 1000;
VARopt.sr_draw = 10000000;
VARopt.sr_hor    = 12;
set(0,'DefaultFigureWindowStyle','normal');
VARopt.quality   = 0;

%% 5) Restricciones de signo para los 4 choques NO identificados por IV
% ------------------------------------------------------------------------
%              Demanda  Oferta  Expectativas  TipoCambio
R = [            1,       -1,        0,            0   ;    % brecha_igae (actividad)
                 1,        1,        0,            0   ;    % sub (inflación)
                 1,        0,        0,            0   ;    % tasa (sin restricción)
                 0,        0,        0,            0   ;    % exp
                 0,        0,        0,            1  ];    % brecha_tcr


%% 5) Restricciones de signo para los 4 choques NO identificados por IV
% ------------------------------------------------------------------------
%              Demanda  Oferta  Expectativas  TipoCambio
%R = [            1,        0,        0,            1   ;    % brecha_igae (actividad)
%                 1,        1,        0,            0   ;    % sub (inflación)
%                 1,        1,        0,            0   ;    % tasa (sin restricción)
%                 0,        0,        0,            0   ;    % exp
%                -1,       -1,        0,            1  ];    % brecha_tcr

VARopt.snames = {'Pol\''itica Monetaria','Demanda','Oferta','Expectativas','Tipo de Cambio'};
VARopt.ident = 'sign+iv';
VARopt.R     = R;

%% 6) Estimación por ventana
% ------------------------------------------------------------------------
VAR_sub = cell(n_ventanas,1);

for k = 1:n_ventanas
    fprintf('\n--- Estimando ventana %d/%d (%s) ---\n', k, n_ventanas, ventana_lbl{k});
    Xk    = X(idx{k}, :);
    mpsk  = mps(idx{k});
    DUMk  = DUM_covid(idx{k});          % <-- recorte de la dummy para esta ventana
    VARopt.IV      = mpsk;
    VARopt.figname = sprintf('graphics/svar_sign_iv_trimestral_%s', strrep(ventana_lbl{k}, '-', '_'));
    VAR_sub{k} = VARmodel(Xk, nlags, detc, VARopt, DUMk, 0); 

    % --- Chequeo de estabilidad (eigenvalues de la matriz companion) ---
    maxEig_k = VAR_sub{k}.maxEig;
    eig_all_k = eig(VAR_sub{k}.Fcomp);

    if maxEig_k < 1
        estado_str = 'ESTABLE';
    else
        estado_str = 'INESTABLE';
    end

    fprintf('Ventana %d (%s): max|eigenvalue| = %.4f -> VAR %s\n', ...
        k, ventana_lbl{k}, maxEig_k, estado_str);

    if maxEig_k >= 1
        warning(['Ventana %d (%s): el VAR es INESTABLE (max|eigenvalue| = %.4f >= 1). ' ...
                 'Los IRFs, FEVD y HD de esta ventana no est\''an bien definidos. ' ...
                 'Considera reducir el n\''umero de rezagos o revisar la transformaci\''on ' ...
                 'de las variables en esta submuestra.'], ...
                 k, ventana_lbl{k}, maxEig_k);
    end

    % --- F-stat de primera etapa (ya existente) ---
    fprintf('F-stat de primera etapa (ventana %d): %.4f\n', k, VAR_sub{k}.FirstStage.F);
    if VAR_sub{k}.FirstStage.F < 10
        warning('Ventana %d (%s): F-stat de primera etapa < 10; instrumento posiblemente débil en este periodo.', ...
            k, ventana_lbl{k});
    end
end

%% 6.1) Resumen de estabilidad y fuerza del instrumento por ventana
% ------------------------------------------------------------------------
maxEig_all  = cellfun(@(v) v.maxEig, VAR_sub);
Fstat_all   = cellfun(@(v) v.FirstStage.F, VAR_sub);
estable_all = maxEig_all < 1;

StabilitySummary = table(ventana_lbl(:), maxEig_all, estable_all, Fstat_all, ...
    'VariableNames', {'Ventana','MaxEigenvalue','Estable','F_stat_1a_etapa'});
disp(StabilitySummary);
%% 7) IRFs individuales de cada ventana (choque 1 = política monetaria)
% ------------------------------------------------------------------------
VARopt.pick = 1;
for k = 1:n_ventanas
    VARopt.figname = sprintf('graphics/svar_sign_iv_trimestral_%s', strrep(ventana_lbl{k}, '-', '_'));
    VARirplot(VAR_sub{k}.IRmed, VARopt, VAR_sub{k}.IRinf, VAR_sub{k}.IRsup);
end

%% 7.1) IRFs completas (los 5 choques) para la ÚLTIMA ventana
% ------------------------------------------------------------------------
% A diferencia de la sección 7 (que solo grafica el choque 1, comparable
% entre todas las ventanas), aquí se grafican los 5 choques de la ventana
% más reciente: política monetaria (interpretación estructural garantizada
% por el IV) y demanda/oferta/expectativas/tipo de cambio (identificados
% por las restricciones de signo de R, condicionales al IV).
k_ultima = n_ventanas;
VARopt.figname = sprintf('graphics/svar_sign_iv_trimestral_%s', strrep(ventana_lbl{k_ultima}, '-', '_'));
for s = 1:nvars
    VARopt.pick = s;
    VARirplot(VAR_sub{k_ultima}.IRmed, VARopt, VAR_sub{k_ultima}.IRinf, VAR_sub{k_ultima}.IRsup);
end

%% 8) Gráfica comparativa: IRF de política monetaria, todas las ventanas móviles
% ------------------------------------------------------------------------
% Con ventanas móviles puede haber muchas más de 3 ventanas, así que los
% colores/estilos ahora se generan dinámicamente (gradiente de color según
% el orden temporal de la ventana) en vez de estar fijos a 3.
h_steps = 0:(VARopt.nsteps-1);
colores = parula(n_ventanas);     % un color por ventana, degradado en el tiempo
estilo  = '-';                    % mismo estilo de línea para todas; el color distingue

fig_comp = figure('Name', 'Comparación IRF: Política Monetaria, ventanas móviles (trimestral)');
for i = 1:nvars
    subplot(ceil(nvars/2), 2, i); hold on;

    h_lines = gobjects(n_ventanas,1);
    for k = 1:n_ventanas
        % Con muchas ventanas traslapadas las bandas de confianza se
        % amontonan y no se leen bien; se omiten aquí y solo se muestran
        % las medianas (las bandas siguen disponibles ventana por ventana
        % en la sección 7 y 9).
        h_lines(k) = plot(h_steps, squeeze(VAR_sub{k}.IRmed(:,i,1)), ...
             'Color', colores(k,:), 'LineWidth', 1.5, 'LineStyle', estilo);
    end

    yline(0, 'k:', 'LineWidth', 0.8);
    title(Xvnames{i}, 'Interpreter', 'latex');
    xlabel('Trimestres'); grid on;
    if i == 1
        % Con muchas ventanas, una leyenda con todas las etiquetas es
        % ilegible; se usa una barra de color en su lugar.
        if n_ventanas <= 6
            legend(h_lines, ventana_lbl, 'Location', 'best', 'FontSize', 7);
        else
            colormap(gca, colores);
            cb = colorbar('Ticks', linspace(0,1,n_ventanas), ...
                           'TickLabels', ventana_lbl, 'FontSize', 6);
            cb.Label.String = 'Ventana';
        end
    end
end
sgtitle('Respuesta a un choque de Pol\''itica Monetaria: ventanas m\''oviles de 10 a\~nos', 'Interpreter', 'latex');

if ~exist('graphics', 'dir'); mkdir('graphics'); end
print(fig_comp, '-dpdf', 'graphics/svar_sign_iv_trimestral_comparacion_ventanas_moviles.pdf');

%% 9) IRFs con bandas de confianza 68% y 90% superpuestas (todas las ventanas)
% ------------------------------------------------------------------------
% AVISO: con ventanas móviles esto genera n_ventanas x nvars figuras/PDFs.
% Si solo te interesan unas pocas ventanas, pon
% `generar_bandas_68_90 = false` y ajusta `ventanas_a_graficar` para elegir
% manualmente los índices de ventana.
generar_bandas_68_90 = true;
ventanas_a_graficar  = 1:n_ventanas;   % <-- o, p.ej., [1, round(n_ventanas/2), n_ventanas]

if generar_bandas_68_90
fprintf('\nSección 9 generará %d figuras (%d ventanas x %d choques).\n', ...
    numel(ventanas_a_graficar)*nvars, numel(ventanas_a_graficar), nvars);

VARopt_68 = VARopt; VARopt_68.pctg = 68;
VARopt_90 = VARopt; VARopt_90.pctg = 90;

VAR_68 = cell(n_ventanas,1);
VAR_90 = cell(n_ventanas,1);

for k = ventanas_a_graficar
    fprintf('\n--- Recalculando bandas 68%% y 90%% para ventana %d (%s) ---\n', k, ventana_lbl{k});
    Xk   = X(idx{k}, :);
    mpsk = mps(idx{k});
    DUMk = DUM_covid(idx{k});

    VARopt_68.IV = mpsk;
    VARopt_90.IV = mpsk;

    VAR_68{k} = VARmodel(Xk, nlags, detc, VARopt_68, DUMk, 0);
    VAR_90{k} = VARmodel(Xk, nlags, detc, VARopt_90, DUMk, 0);
end

%% 9.1) Gráfica: un figure por ventana, subpanel por variable, todos los choques
% ------------------------------------------------------------------------
h_steps = 0:(VARopt.nsteps-1);
color_90 = [0.30 0.30 0.30];   % gris claro para banda 90%
color_68 = [0.10 0.35 0.75];   % azul para banda 68% y la mediana

for k = ventanas_a_graficar
    for s = 1:nvars   % s = índice del choque (política, demanda, oferta, expectativas, tc)

        fig_conf = figure('Name', sprintf('IRF %s - Choque %s - Bandas 68%%/90%% (%s)', ...
            Xvnames{1}, VARopt.snames{s}, ventana_lbl{k}));

        for i = 1:nvars   % i = índice de la variable de respuesta

            subplot(ceil(nvars/2), 2, i); hold on;

            med  = squeeze(VAR_68{k}.IRmed(:, i, s));
            lo90 = squeeze(VAR_90{k}.IRinf(:, i, s));
            hi90 = squeeze(VAR_90{k}.IRsup(:, i, s));
            lo68 = squeeze(VAR_68{k}.IRinf(:, i, s));
            hi68 = squeeze(VAR_68{k}.IRsup(:, i, s));

            % Banda 90% (más ancha, más clara, va debajo)
            fill([h_steps, fliplr(h_steps)], [lo90', fliplr(hi90')], ...
                 color_90, 'FaceAlpha', 0.15, 'EdgeColor', 'none');

            % Banda 68% (más angosta, más oscura, va encima)
            fill([h_steps, fliplr(h_steps)], [lo68', fliplr(hi68')], ...
                 color_68, 'FaceAlpha', 0.30, 'EdgeColor', 'none');

            % Mediana
            plot(h_steps, med, 'Color', color_68, 'LineWidth', 1.8);

            yline(0, 'k:', 'LineWidth', 0.8);
            title(Xvnames{i}, 'Interpreter', 'latex');
            xlabel('Trimestres'); grid on;

            if i == 1
                % Leyenda manual (fill no siempre se lleva bien con legend automática)
                h_leg90 = fill(nan, nan, color_90, 'FaceAlpha', 0.15, 'EdgeColor', 'none');
                h_leg68 = fill(nan, nan, color_68, 'FaceAlpha', 0.30, 'EdgeColor', 'none');
                legend([h_leg90, h_leg68], {'90%', '68%'}, 'Location', 'best', 'FontSize', 7);
            end
        end

        sgtitle(sprintf('Respuesta a choque de %s (%s): bandas 68%% y 90%%', ...
            VARopt.snames{s}, ventana_lbl{k}), 'Interpreter', 'latex');

        if ~exist('graphics', 'dir'); mkdir('graphics'); end
        nombre_choque = strrep(strrep(VARopt.snames{s}, ' ', '_'), '\''', '');
        print(fig_conf, '-dpdf', sprintf('graphics/svar_sign_iv_%s_choque_%s_bandas68_90.pdf', ...
            strrep(ventana_lbl{k}, '-', '_'), nombre_choque));
    end
end
end % if generar_bandas_68_90