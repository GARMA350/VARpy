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
%  El tipo de cambio real (tcr, ya en logaritmos L_TCR) se transforma de la
%  MISMA manera a BRECHA DEL TCR mediante el mismo filtro HP.
%  Ambas brechas (no los niveles/log-niveles) son las que se usan en el VAR.
%
%  Choque de política monetaria  -> identificado con el instrumento externo mps
%  Choques restantes (4)         -> identificados con restricciones de signo,
%                                    condicionales al choque ya fijado por el IV
%
%  ANÁLISIS DE ESTABILIDAD: se comparan TRES ventanas de muestra:
%    Ventana 1: 2008-2018
%    Ventana 2: 2012-2022
%    Ventana 3: 2016-2026
%  NOTA: las ventanas 2 y 3 SE TRASLAPAN entre sí (2016-2022 está en ambas),
%  así que esto es una comparación de periodos parcialmente superpuestos
%  ("rolling"), no una partición en submuestras independientes.
%
%  Para la ÚLTIMA ventana (2016-2026) se reportan además todas las IRFs
%  (los 5 choques) y la descomposición histórica.
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
exp      = Ttab.exp12_g;               % expectativas
tcr      = Ttab.diff_ln_tcn;               % tipo de cambio real (en logaritmos, L_TCR)
mps      = Ttab.mps*-1;               % instrumento externo (monetary policy shock, sumado por trimestre)

T = height(Ttab);

mnem = {'igae','inf','tasa','exp','l_tcr','mps'};

%% 1.0) Gráfica exploratoria de las series originales
% ------------------------------------------------------------------------
fig_raw = figure('Name','Series originales (trimestral)');
vars_raw  = {igae, inf, tasa, exp, tcr, mps};
names_raw = {'IGAE (nivel)','Inflacion','Tasa de interes', ...
             'Exp. Inflacion','log TCR','mps (instrumento)'};
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
%{
% --- Tipo de cambio real: brecha del TCR ---
% 'tcr' ya viene en logaritmos (L_TCR = L_S + L_CPI_RW - L_CPI, generado
% previamente). Se aplica el MISMO filtro HP trimestral y se usa el
% componente CÍCLICO (brecha del TCR), no el nivel/log-nivel, para
% mantener consistencia de orden de integración con el resto del sistema.
[tcr_trend, tcr_cycle] = hpfilter(tcr, 'Smoothing', lambda_hp);
% Sintaxis antigua: [tcr_trend, tcr_cycle] = hpfilter(log_tcr, lambda_hp);
brecha_tcr = tcr_cycle;        % brecha en % (log-desviación * 100)
%}
tcr_label  = 'TCR (filtro HP, \lambda=14400)';

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
plot(dates_dt, tcr, 'k', dates_dt, tcr, 'r--', 'LineWidth', 1.2);
title('L\_TCR: serie y tendencia HP', 'Interpreter','latex'); grid on;
legend('L\_TCR','Tendencia','Location','best');

subplot(2,2,4);
plot(dates_dt, tcr, 'b', 'LineWidth', 1.2); yline(0,'k:');
title(tcr_label, 'Interpreter','latex'); grid on;

sgtitle('Descomposici\''on HP ($\lambda=1600$): actividad y TCR', 'Interpreter','latex');
print(fig_hp, '-dpdf', 'graphics/descomposicion_hp_igae_tcr_trimestral.pdf');

%% 1.2) Chequeo de estacionariedad (ADF + KPSS) de todas las series
% ------------------------------------------------------------------------
series_test = {actividad, inf, tasa, exp, tcr, mps};
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
X = [actividad, inf, tasa, exp, tcr];
Xmnem   = {'brecha_igae','inf','tasa','exp','tcr'};
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
nlags = 1;               % <-- AJUSTA con base en el resultado de VARlag (4 trim. = 1 año es un punto de partida típico)
detc  = 1;               % 1 = constante


%% 1.4) Dummy Crisis Financiera Global + COVID
% ------------------------------------------------------------------------
% Impulse dummy: vale 1 en dic-2008 a mar-2010 (GFC) y en mar-may 2020 (COVID),
% 0 en el resto. Captura los choques atípicos de esos periodos sin dejar
% un "escalón" permanente en el resto de la muestra.

% Rango 1: diciembre 2008 a marzo 2010 (16 meses)
fechas_gfc1 = (datetime(2008,10,1) : calmonths(1) : datetime(2008,12,1))';
fechas_gfc2 = (datetime(2009,4,1) : calmonths(1) : datetime(2009,5,1))';

% Rango 2: marzo, abril y mayo 2020 (3 meses)
fechas_covid = (datetime(2020,3,1) : calmonths(1) : datetime(2020,5,1))';

fechas_post = (datetime(2021,3,1) : calmonths(1) : datetime(2023,1,1))';

fechas_dummy = [fechas_gfc1; fechas_gfc2;];

DUM_covid = zeros(T,1);
DUM_covid(ismember(dates_dt, fechas_dummy)) = 1;

n_esperado = numel(fechas_dummy); % 16 + 3 = 19
if sum(DUM_covid) ~= n_esperado
    warning(['La dummy no encontró exactamente %d meses (encontró %d). ' ...
        'Revisa que las fechas en dates_dt correspondan al primer día de cada mes.'], ...
        n_esperado, sum(DUM_covid));
end

%% 3) Definición de las ventanas de muestra
% ------------------------------------------------------------------------
fecha_min_datos = dates_dt(1);
fecha_max_datos = dates_dt(T);

%% 3) Definición de las ventanas de muestra
% ------------------------------------------------------------------------
n_ventanas = 1;
ventana_ini = datetime(2008,1,1);
ventana_fin = datetime(2016,6,30);   % <-- corregido: fin de año, no 1-ene
ventana_lbl = {'2008-2016'};                       % <-- corregido: coincide con fechas reales
idx = cell(n_ventanas,1);
for k = 1:n_ventanas
    if ventana_ini(k) < fecha_min_datos || ventana_fin(k) > fecha_max_datos
        warning(['Ventana %s excede el rango disponible en los datos (%s a %s). ' ...
                 'Se recortará automáticamente a lo disponible.'], ...
                 ventana_lbl{k}, datestr(fecha_min_datos, 'yyyy-mm'), datestr(fecha_max_datos, 'yyyy-mm'));
    end
    idx{k} = find(dates_dt >= ventana_ini(k) & dates_dt <= ventana_fin(k));
    if isempty(idx{k})
        error('Ventana %s no tiene observaciones dentro del rango de datos disponible.', ventana_lbl{k});
    end
end

fprintf('\n--- Ventanas de muestra (trimestral) ---\n');
for k = 1:n_ventanas
    fprintf('Ventana %d (solicitada %s): %s a %s, n = %d trimestres\n', ...
        k, ventana_lbl{k}, datestr(dates_dt(idx{k}(1)), 'yyyy-mm'), ...
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

%% 4) Opciones generales del VAR (compartidas por las tres ventanas)
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
VARopt.ndraws    = 500;
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

%{
for k = 1:n_ventanas
    fprintf('\n--- Estimando ventana %d (%s) ---\n', k, ventana_lbl{k});
    Xk    = X(idx{k}, :);
    mpsk  = mps(idx{k});
    VARopt.IV      = mpsk;
    VARopt.figname = sprintf('graphics/svar_sign_iv_trimestral_%s', strrep(ventana_lbl{k}, '-', '_'));
    VAR_sub{k} = VARmodel(Xk, nlags, detc, VARopt);   % <-- sin EXOG, sin nlag_ex
%}

for k = 1:n_ventanas
    fprintf('\n--- Estimando ventana %d (%s) ---\n', k, ventana_lbl{k});
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
% entre las tres ventanas), aquí se grafican los 5 choques de la ventana
% más reciente (2016-2026): política monetaria (interpretación estructural
% garantizada por el IV) y demanda/oferta/expectativas/tipo de cambio
% (identificados por las restricciones de signo de R, condicionales al IV).
k_ultima = n_ventanas;   % 2016-2026
VARopt.figname = sprintf('graphics/svar_sign_iv_trimestral_%s', strrep(ventana_lbl{k_ultima}, '-', '_'));
for s = 1:nvars
    VARopt.pick = s;
    VARirplot(VAR_sub{k_ultima}.IRmed, VARopt, VAR_sub{k_ultima}.IRinf, VAR_sub{k_ultima}.IRsup);
end

%% 8) Gráfica comparativa: IRF de política monetaria, las tres ventanas
% ------------------------------------------------------------------------
h_steps = 0:(VARopt.nsteps-1);
colores = [0.10 0.35 0.75;    % azul:   ventana 1
           0.80 0.25 0.10;    % rojo:   ventana 2
           0.15 0.60 0.25];   % verde:  ventana 3
estilos = {'-', '--', ':'};

fig_comp = figure('Name', 'Comparación IRF: Política Monetaria, 3 ventanas (trimestral)');
for i = 1:nvars
    subplot(ceil(nvars/2), 2, i); hold on;

    h_lines = gobjects(n_ventanas,1);
    for k = 1:n_ventanas
        fill([h_steps, fliplr(h_steps)], ...
             [squeeze(VAR_sub{k}.IRinf(:,i,1))', flipud(squeeze(VAR_sub{k}.IRsup(:,i,1)))'], ...
             colores(k,:), 'FaceAlpha', 0.12, 'EdgeColor', 'none');
        h_lines(k) = plot(h_steps, squeeze(VAR_sub{k}.IRmed(:,i,1)), ...
             'Color', colores(k,:), 'LineWidth', 1.8, 'LineStyle', estilos{k});
    end

    yline(0, 'k:', 'LineWidth', 0.8);
    title(Xvnames{i}, 'Interpreter', 'latex');
    xlabel('Trimestres'); grid on;
    if i == 1
        legend(h_lines, ventana_lbl, 'Location', 'best', 'FontSize', 7);
    end
end
sgtitle('Respuesta a un choque de Pol\''itica Monetaria: comparaci\''on de ventanas', 'Interpreter', 'latex');

if ~exist('graphics', 'dir'); mkdir('graphics'); end
print(fig_comp, '-dpdf', 'graphics/svar_sign_iv_trimestral_comparacion_3ventanas.pdf');

%% 9) IRFs con bandas de confianza 68% y 90% superpuestas (todas las ventanas)
% ------------------------------------------------------------------------
% Se corre VARmodel dos veces por ventana: una para pctg=68, otra para
% pctg=90. La mediana (IRmed) es prácticamente idéntica entre ambas
% corridas (mismo VARopt.method='wild', mismo modelo puntual); lo único
% que cambia es el ancho de las bandas. Se grafican superpuestas: banda
% 90% (más clara/ancha) por debajo, banda 68% (más oscura/angosta) encima.

VARopt_68 = VARopt; VARopt_68.pctg = 68;
VARopt_90 = VARopt; VARopt_90.pctg = 90;

VAR_68 = cell(n_ventanas,1);
VAR_90 = cell(n_ventanas,1);

for k = 1:n_ventanas
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
% Para cada ventana se genera UN figure por choque (5 choques), con
% subpaneles de las 5 variables, superponiendo banda 90% (clara) y
% banda 68% (oscura) alrededor de la misma mediana.

h_steps = 0:(VARopt.nsteps-1);
color_90 = [0.30 0.30 0.30];   % gris claro para banda 90%
color_68 = [0.10 0.35 0.75];   % azul para banda 68% y la mediana

for k = 1:n_ventanas
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
