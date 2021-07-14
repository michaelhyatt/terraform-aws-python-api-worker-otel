import logging
import os
import requests

# Sleeps are not required there, they are only used to make traces look nice in Kibana
import time

from json import dumps

from opentelemetry import trace
from opentelemetry.trace import SpanKind
from opentelemetry.propagate import inject, extract

logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

URL = os.getenv('CONSUMER_API')


def producer(event, lambda_context):

    context = extract(event['headers'])

    logger.debug(f'Context: {context}')

    tracer = trace.get_tracer(__name__)

    # Create the top-level transaction representing the lambda work
    with tracer.start_as_current_span(name="producer-function-top-level", context=context, kind=SpanKind.SERVER):

        logger.debug(f'Message: {dumps(event)}')

        time.sleep(0.5)

        # Create client span - only if autoinstrumentation is turned off
        # Requires indentation of the underlying block until return
        # with tracer.start_as_current_span(name="producer-function-client", kind=SpanKind.CLIENT) as span:
        request_to_downstream = requests.Request(method="GET", url=URL, 
        headers={
            "Content-Type": "application/json"
        })

        # Autoinstrumentation takes care of the following, but
        #  if it is turned off, inject the context into headers manually
        #  and set few attributes to allow the service maps to detect the
        #  direction of the call
        #
        # Required for the caller to be recognised in service maps
        # span.set_attribute("http.method", request_to_downstream.method)
        # span.set_attribute("http.url", request_to_downstream.url)
        # Inject the right trace header into the request
        # inject(request_to_downstream.headers)

        logger.debug(f'Outbound headers: {dumps(request_to_downstream.headers)}')

        session = requests.Session()

        res = session.send(request_to_downstream.prepare())

        # Only required if autoinstrumentation is switched off
        # Required for the caller to be recognised in service maps
        # span.set_attribute("http.status_code", res.status_code)

        time.sleep(0.3)

    return {'statusCode': res.status_code}


def consumer(event, lambda_context):

    context = extract(event['headers'])

    logger.debug(f'Context: {context}')

    tracer = trace.get_tracer(__name__)

    # Create top level transaction representing the lambda work
    with tracer.start_as_current_span("consumer-function-top-level", context=context, kind=SpanKind.SERVER):

        time.sleep(1)

        # Some other internal work performed by the lambda
        with tracer.start_as_current_span("consumer-function-some-internal-work", kind=SpanKind.INTERNAL):

            logger.debug(f'Message: {dumps(event)}')

            time.sleep(1)

        time.sleep(0.5)

    return {'statusCode': 200}
