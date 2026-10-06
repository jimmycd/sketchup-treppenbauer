# Prüft Drachenstufen: jede Ecke liegt in genau einer Stufe, an Innen- und Außenecke
# beide Schenkel mind. qmin (2 cm). mid: true -> Ecke zusätzlich mittig und symmetrisch.
module KiteCheck
  include JTools::Treppenbau
  module_function
  # Rückgabe: Liste von Fehlertexten
  def errors(plan, qmin = 1.99, mid: false)
    errs = []
    return errs if plan.corners.nil? || plan.corners.empty?
    f = plan.walk.length / plan.lines_w[-1]
    plan.corners.each_with_index do |c, ci|
      next unless plan.zones.any? { |z| z[:kind] == :winder && c[:w] && c[:w] > z[:w0] - 1e-6 && c[:w] < z[:w1] + 1e-6 }
      lw = plan.lines_w
      k = (0...plan.treads).find { |j| plan.line(lw[j])[:t] < c[:t] - 1e-6 && plan.line(lw[j + 1])[:t] > c[:t] + 1e-6 }
      unless k
        errs << "Ecke #{ci + 1}: Stufenkante läuft durch die Außenecke"
        next
      end
      wm = (lw[k] + lw[k + 1]) / 2.0
      errs << format('Ecke %d: Drachenstufe nicht mittig (%.2f cm)', ci + 1, wm - c[:w]) if mid && (wm - c[:w]).abs > 0.02
      l0 = plan.line(lw[k]); l1 = plan.line(lw[k + 1])
      q0 = c[:s] - l0[:s]; q1 = l1[:s] - c[:s]
      errs << format('Ecke %d: Innenseite unsymmetrisch (%.2f / %.2f)', ci + 1, q0, q1) if mid && (q0 - q1).abs > 0.05
      [q0, q1].each { |q| errs << format('Ecke %d: kleiner Schenkel innen %.2f cm', ci + 1, q) if q < qmin }
      # Innenseite im selben Verhältnis geteilt wie die Gehlinie
      f = (c[:w] - lw[k]) / (lw[k + 1] - lw[k])
      errs << format('Ecke %d: Teilung innen %.3f ≠ Gehlinie %.3f', ci + 1, q0 / (q0 + q1), f) if q0 + q1 > 0.1 && (q0 / (q0 + q1) - f).abs > 0.002
      errs << format('Ecke %d: Innenecke nicht in der Drachenstufe (%.2f / %.2f)', ci + 1, q0, q1) if q0 < -0.05 || q1 < -0.05
      o0 = c[:t] - l0[:t]; o1 = l1[:t] - c[:t]
      [o0, o1].each { |o| errs << format('Ecke %d: kleiner Schenkel außen %.2f cm', ci + 1, o) if o < qmin }
    end
    # Auftritt auf der Gehlinie = a (keine stille Umskalierung)
    if plan.kinds.all? { |k| k == :step }
      d = (plan.lines_w[1] - plan.lines_w[0]) - plan.a
      errs << format('Auftritt auf der Gehlinie weicht um %.2f cm von a ab', d) if d.abs > 0.05
    end
    # Kanten dürfen sich nicht kreuzen (s und t monoton)
    ls = plan.lines_w.map { |w| plan.line(w) }
    (0...ls.size - 1).each do |j|
      errs << "Stufe #{j + 1}: Innenauftritt negativ" if ls[j + 1][:s] < ls[j][:s] - 1e-6
      errs << "Stufe #{j + 1}: Außenauftritt negativ" if ls[j + 1][:t] < ls[j][:t] - 1e-6
    end
    errs
  end
end
