Dir['out/tcn_*/*.tcn'].each do |f|
  t = File.read(f, encoding: 'Windows-1252')
  dl = t[/DL=([\d.]+)/,1].to_f; dh = t[/DH=([\d.]+)/,1].to_f
  cur=nil; bad=0; n=0; oob=0
  blocks=[]
  t.each_line do |l|
    if l =~ /W#89\{.*#1=(\S+) #2=(\S+) #3=(\S+).*#40=(\d)/
      blocks << {start:[$1.to_f,$2.to_f], p:[$1.to_f,$2.to_f], comp:$4.to_i}
    elsif l =~ /W#2201\{.*#1=(\S+) #2=(\S+)/
      b=blocks[-1]; b[:p]=[b[:p][0]+$1.to_f, b[:p][1]+$2.to_f]
      oob+=1 if b[:p][0]< -0.01 || b[:p][0]>dl+0.01 || b[:p][1]< -0.01 || b[:p][1]>dh+0.01
    end
  end
  blocks.each{|b| next unless b[:comp]>0; n+=1; d=Math.hypot(b[:p][0]-b[:start][0], b[:p][1]-b[:start][1]); bad+=1 if d>0.005}
  puts "#{File.basename(f)}: konturen=#{n} offen=#{bad} ausserhalb=#{oob}"
end
