@echo off
rem Windows twin of build.sh: {network,vpc} x {fargate,eks} x {r53,dns} x {basic,marketplace}.
cd /d "%~dp0"
for %%n in (network:create_network vpc:choose_vpc) do (
  for /f "tokens=1,2 delims=:" %%a in ("%%n") do (
    for %%c in (fargate eks) do (
      for %%d in (r53 dns) do (
        for %%o in (basic marketplace) do (
          py templates/cf_template_merge.py -i templates/%%b.template.yml -i templates/common.template.yml -i templates/%%c.template.yml -i templates/%%d.template.yml -i templates/%%o.template.yml -i templates/versions.template.yml -o %%a-%%c-%%d-%%o.yml
        )
      )
    )
  )
)
